import 'dart:convert';
import 'dart:typed_data';

import 'package:spend_trends/services/simplefin/simplefin_models.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:http/http.dart' as http;

const _logger = ELogger('SimpleFinClient');

/// Bridge dashboard — add / re-link banks here (no in-app widget).
const simpleFinBridgeUrl = 'https://bridge.simplefin.org/';

/// One-time Setup Token page for claiming a new Access URL.
const simpleFinCreateUrl = 'https://bridge.simplefin.org/simplefin/create';

class const _FetchWindow({final int? startUnix, final int? endUnix});

class SimpleFinClient({http.Client? httpClient}) {
  final http.Client _httpClient = httpClient ?? http.Client();

  Future<Uri> claimAccessUrl(String setupToken) async {
    final claimUrl = _decodeClaimUrl(setupToken);
    _logger.log('Claim POST ${_redactUri(claimUrl)}');
    final response = await _postClaim(claimUrl);
    return _accessUrlFromClaimResponse(response);
  }

  Future<http.Response> _postClaim(Uri claimUrl) async {
    try {
      return await _httpClient.post(
        claimUrl,
        headers: const {'Content-Length': '0'},
      );
    } catch (error, stackTrace) {
      _logger.error('Claim request failed', error, stackTrace);
      rethrow;
    }
  }

  Uri _accessUrlFromClaimResponse(http.Response response) {
    final accessUrlText = response.body.trim();
    final parsedAccessUrl = Uri.tryParse(accessUrlText);
    _logClaimResponse(response, accessUrlText, parsedAccessUrl);

    final accessUrl = _requireClaimAccessUrl(response, parsedAccessUrl);
    _logger.log(
      'Claimed Access URL host=${accessUrl.host} '
      'path=${accessUrl.path} hasUserInfo=${accessUrl.userInfo.isNotEmpty}',
    );
    return accessUrl;
  }

  void _logClaimResponse(
    http.Response response,
    String accessUrlText,
    Uri? parsedAccessUrl,
  ) {
    final bodySummary =
        parsedAccessUrl != null && parsedAccessUrl.scheme == 'https'
        ? _redactUri(parsedAccessUrl)
        : _truncate(accessUrlText);
    _logger.log(
      'Claim response HTTP ${response.statusCode}, body=$bodySummary',
    );
  }

  /// Throws for non-success claim responses or a non-HTTPS Access URL.
  Uri _requireClaimAccessUrl(http.Response response, Uri? parsedAccessUrl) {
    if (response.statusCode == 403) {
      throw SimpleFinClaimException(
        'Token invalid or already claimed — revoke in SimpleFIN and create a new one.',
        statusCode: 403,
      );
    }
    if (response.statusCode != 200) {
      throw SimpleFinClaimException(
        'Could not claim SimpleFIN token (HTTP ${response.statusCode}): '
        '${_truncate(response.body)}',
        statusCode: response.statusCode,
      );
    }
    if (parsedAccessUrl == null || parsedAccessUrl.scheme != 'https') {
      _logger.warn('Claim returned non-HTTPS Access URL');
      throw SimpleFinClaimException(
        'SimpleFIN returned an invalid Access URL.',
      );
    }
    return parsedAccessUrl;
  }

  Future<SimpleFinAccountSet> fetchAccounts({
    required Uri accessUrl,
    DateTime? start,
    DateTime? end,
    bool pending = true,
    bool balancesOnly = false,
    List<String> accountIds = const [],
    void Function(int bytesReceived, int? contentLength)? onBytes,
  }) async {
    if (accessUrl.scheme != 'https') {
      throw SimpleFinFetchException('Access URL must use HTTPS.');
    }

    final window = _clampedFetchWindow(start: start, end: end);
    _logFetchWindow(window);

    final requestUrl = _accountsRequestUrl(
      accessUrl: accessUrl,
      window: window,
      pending: pending,
      balancesOnly: balancesOnly,
      accountIds: accountIds,
    );
    final response = await _getAccountsResponse(
      accessUrl: accessUrl,
      requestUrl: requestUrl,
      onBytes: onBytes,
    );
    return _accountSetFromResponse(response);
  }

  void _logFetchWindow(_FetchWindow window) {
    if (window.startUnix == null || window.endUnix == null) return;
    final spanSeconds = window.endUnix! - window.startUnix!;
    _logger.log(
      'Fetch window startUnix=${window.startUnix} endUnix=${window.endUnix} '
      'spanSeconds=$spanSeconds spanDays≈${spanSeconds / 86400}',
    );
  }

  _FetchWindow _clampedFetchWindow({DateTime? start, DateTime? end}) {
    // beta-bridge: "exceeds recommended range of 45 days" for spans >= 45d.
    const maxSpanSeconds = 44 * 24 * 60 * 60;
    var startUnix = start == null ? null : start.millisecondsSinceEpoch ~/ 1000;
    final endUnix = end == null ? null : end.millisecondsSinceEpoch ~/ 1000;
    if (startUnix != null &&
        endUnix != null &&
        endUnix - startUnix > maxSpanSeconds) {
      final clampedStartUnix = endUnix - maxSpanSeconds;
      _logger.warn(
        'Clamping start-date from $startUnix to $clampedStartUnix '
        '(max span ${maxSpanSeconds}s)',
      );
      startUnix = clampedStartUnix;
    }
    return _FetchWindow(startUnix: startUnix, endUnix: endUnix);
  }

  Uri _accountsRequestUrl({
    required Uri accessUrl,
    required _FetchWindow window,
    required bool pending,
    required bool balancesOnly,
    required List<String> accountIds,
  }) {
    final queryParts = <String>['version=2'];
    if (pending) queryParts.add('pending=1');
    if (balancesOnly) queryParts.add('balances-only=1');
    if (window.startUnix != null) {
      queryParts.add('start-date=${window.startUnix}');
    }
    if (window.endUnix != null) queryParts.add('end-date=${window.endUnix}');
    for (final accountId in accountIds) {
      if (accountId.isEmpty) continue;
      queryParts.add('account=${Uri.encodeQueryComponent(accountId)}');
    }

    final accountsPath = _joinPath(accessUrl.path, 'accounts');
    return Uri(
      scheme: accessUrl.scheme,
      host: accessUrl.host,
      port: accessUrl.hasPort ? accessUrl.port : null,
      path: accountsPath,
      query: queryParts.join('&'),
    );
  }

  Future<http.Response> _getAccountsResponse({
    required Uri accessUrl,
    required Uri requestUrl,
    void Function(int bytesReceived, int? contentLength)? onBytes,
  }) async {
    final headers = _accountsRequestHeaders(accessUrl);
    _logger.log(
      'GET ${_redactUri(requestUrl)} auth=${headers.containsKey('Authorization')}',
    );

    final request = http.Request('GET', requestUrl);
    request.headers.addAll(headers);
    try {
      final streamed = await _httpClient.send(request);
      final contentLength = streamed.contentLength;
      final body = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in streamed.stream) {
        body.add(chunk);
        received += chunk.length;
        onBytes?.call(received, contentLength);
      }
      return http.Response.bytes(
        body.takeBytes(),
        streamed.statusCode,
        headers: streamed.headers,
        request: request,
      );
    } catch (error, stackTrace) {
      _logger.error('Fetch request failed', error, stackTrace);
      rethrow;
    }
  }

  Map<String, String> _accountsRequestHeaders(Uri accessUrl) {
    final basicAuth = _basicAuthHeader(accessUrl);
    if (basicAuth == null) {
      _logger.warn('Access URL has no userInfo; request may be unauthorized');
      return const {};
    }
    return {'Authorization': basicAuth};
  }

  SimpleFinAccountSet _accountSetFromResponse(http.Response response) {
    _logFetchResponse(response);
    final decoded = _requireAccountSetJson(response);
    _warnIfNonSuccessAccountSet(response);
    return _parsedAccountSetWithLogs(decoded);
  }

  void _logFetchResponse(http.Response response) {
    _logger.log(
      'Fetch response HTTP ${response.statusCode}, '
      'bytes=${response.bodyBytes.length}',
    );
  }

  /// Hard failures (auth/billing/non-JSON). Soft non-200 with a JSON Account
  /// Set body is allowed — beta-bridge returns 400 + errlist for warnings.
  Map<String, dynamic> _requireAccountSetJson(http.Response response) {
    if (response.statusCode == 403) {
      throw SimpleFinFetchException(
        'SimpleFIN access revoked or invalid. Re-link your bank. '
        '${_truncate(response.body)}',
        statusCode: 403,
      );
    }
    if (response.statusCode == 402) {
      throw SimpleFinFetchException(
        'SimpleFIN subscription required. ${_truncate(response.body)}',
        statusCode: 402,
      );
    }

    final decoded = _tryDecodeJsonMap(response.body);
    if (decoded == null) {
      throw SimpleFinFetchException(
        'SimpleFIN fetch failed (HTTP ${response.statusCode}): '
        '${_truncate(response.body)}',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  void _warnIfNonSuccessAccountSet(http.Response response) {
    if (response.statusCode == 200) return;
    _logger.warn(
      'Non-200 Account Set HTTP ${response.statusCode}; parsing body anyway',
    );
  }

  SimpleFinAccountSet _parsedAccountSetWithLogs(Map<String, dynamic> decoded) {
    final accountSet = parseAccountSet(decoded);
    _logger.log(
      'Parsed accounts=${accountSet.accounts.length} '
      'transactions=${accountSet.accounts.fold<int>(0, (sum, account) => sum + account.transactions.length)} '
      'errors=${accountSet.errors.length}',
    );
    for (final error in accountSet.errors) {
      _logger.warn('errlist ${error.code}: ${error.message}');
    }
    return accountSet;
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  /// Visible for tests.
  static SimpleFinAccountSet parseAccountSet(Map<String, dynamic> json) {
    final errlist = (json['errlist'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SimpleFinError.fromJson)
        .toList();

    final connections = (json['connections'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SimpleFinConnection.fromJson)
        .where((connection) => connection.id.isNotEmpty)
        .toList();
    final connectionNameById = {
      for (final connection in connections) connection.id: connection.name,
    };

    final accounts = (json['accounts'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(_parseAccount)
        .map((account) => _withResolvedConnName(account, connectionNameById))
        .toList();

    return SimpleFinAccountSet(
      errors: errlist,
      accounts: accounts,
      connections: connections,
    );
  }

  /// Prefer account `conn_name`; fall back to the matching `connections` entry.
  static SimpleFinAccount _withResolvedConnName(
    SimpleFinAccount account,
    Map<String, String> connectionNameById,
  ) {
    final directName = account.connName?.trim();
    if (directName != null && directName.isNotEmpty) return account;
    final connId = account.connId;
    if (connId == null) return account;
    final fromConnections = connectionNameById[connId]?.trim();
    if (fromConnections == null || fromConnections.isEmpty) return account;
    return account.copyWith(connName: fromConnections);
  }

  static SimpleFinAccount _parseAccount(Map<String, dynamic> json) {
    final transactions = (json['transactions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(_parseTransaction)
        .toList();

    return SimpleFinAccount(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Account',
      currency: json['currency'] as String? ?? 'USD',
      balance: json['balance']?.toString() ?? '0',
      availableBalance: json['available-balance']?.toString(),
      balanceDate: (json['balance-date'] as Object?).asIntOrNull() ?? 0,
      connId: json['conn_id'] as String?,
      connName: json['conn_name'] as String?,
      transactions: transactions,
    );
  }

  static SimpleFinTransaction _parseTransaction(Map<String, dynamic> json) {
    return SimpleFinTransaction(
      id: json['id'] as String? ?? '',
      posted: (json['posted'] as Object?).asIntOrNull() ?? 0,
      amount: json['amount']?.toString() ?? '0',
      description: json['description'] as String? ?? '',
      pending: json['pending'] == true,
    );
  }

  Uri _decodeClaimUrl(String setupToken) {
    final cleaned = _cleanPastedToken(setupToken);
    _logSetupToken(cleaned);
    if (cleaned.isEmpty) {
      throw SimpleFinClaimException('Paste a SimpleFIN Setup Token.');
    }
    if (cleaned.startsWith('https://')) {
      return _requireHttpsClaimUrl(cleaned);
    }
    return _claimUrlFromBase64Token(cleaned);
  }

  void _logSetupToken(String cleaned) {
    _logger.log(
      'Decode Setup Token chars=${cleaned.length} '
      'prefix=${cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned}',
    );
  }

  Uri _requireHttpsClaimUrl(String cleaned) {
    final claimUrl = Uri.tryParse(cleaned);
    if (claimUrl == null || claimUrl.scheme != 'https') {
      throw SimpleFinClaimException('Claim URL must use HTTPS.');
    }
    _logger.log('Setup Token was already an HTTPS URL');
    return claimUrl;
  }

  Uri _claimUrlFromBase64Token(String cleaned) {
    try {
      return _parseDecodedClaimUrl(utf8.decode(_decodeBase64Flexible(cleaned)));
    } on SimpleFinClaimException {
      rethrow;
    } catch (error) {
      _logger.warn('Failed to decode Setup Token: $error');
      throw SimpleFinClaimException(
        'Could not decode Setup Token. Copy the full token from SimpleFIN '
        '(base64, often starts with aHR0). Error: $error',
      );
    }
  }

  Uri _parseDecodedClaimUrl(String decoded) {
    final claimUrl = Uri.parse(decoded.trim());
    if (claimUrl.scheme != 'https') {
      throw SimpleFinClaimException(
        'Decoded token is not an HTTPS claim URL (got ${claimUrl.scheme}).',
      );
    }
    _logger.log('Decoded claim URL ${_redactUri(claimUrl)}');
    return claimUrl;
  }

  static List<int> _decodeBase64Flexible(String value) {
    final normalized = _normalizeBase64(value);
    try {
      return base64.decode(normalized);
    } on FormatException {
      return base64Url.decode(normalized);
    }
  }

  static String _cleanPastedToken(String value) {
    var cleaned = value.trim();
    cleaned = cleaned.replaceFirst(
      RegExp(
        r'^(setup\s*token|token|simplefin)\s*[:=]?\s*',
        caseSensitive: false,
      ),
      '',
    );
    return cleaned
        .replaceAll('\uFEFF', '')
        .replaceAll(RegExp(r'[\u200B-\u200D\u2060]'), '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('"', '')
        .replaceAll("'", '');
  }

  static String _normalizeBase64(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalized.length % 4;
    if (remainder != 0) {
      normalized = normalized.padRight(
        normalized.length + (4 - remainder),
        '=',
      );
    }
    return normalized;
  }

  static String _joinPath(String basePath, String segment) {
    if (basePath.endsWith('/')) return '$basePath$segment';
    if (basePath.isEmpty) return '/$segment';
    return '$basePath/$segment';
  }

  /// Explicit Basic Auth — do not rely on URI userInfo (http package / redirects).
  static String? _basicAuthHeader(Uri accessUrl) {
    final userInfo = accessUrl.userInfo;
    if (userInfo.isEmpty) return null;
    final separator = userInfo.indexOf(':');
    if (separator < 0) return null;
    final username = Uri.decodeComponent(userInfo.substring(0, separator));
    final password = Uri.decodeComponent(userInfo.substring(separator + 1));
    final token = base64.encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }

  static String _redactUri(Uri uri) {
    if (uri.userInfo.isEmpty) return uri.toString();
    return uri.replace(userInfo: '***:***').toString();
  }

  static String _truncate(String value, [int maxChars = 400]) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxChars) return compact;
    return '${compact.substring(0, maxChars)}…';
  }

  void close() => _httpClient.close();
}
