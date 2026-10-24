class const SimpleFinError({
  required final String code,
  required final String message,
  final String? connId,
  final String? accountId,
}) {
  static final _connectionAttention = RegExp(
    r'^Connection to (.+?) may need attention\b',
    caseSensitive: false,
  );

  bool get isAuthFailure =>
      code == 'con.auth' || code.startsWith('con.auth') || code == 'gen.auth';

  /// SimpleFIN is asking for new bank credentials.
  bool get asksToReauthenticate {
    if (isAuthFailure) return true;
    final lower = message.toLowerCase();
    return lower.contains('auth required') ||
        lower.contains('authentication required');
  }

  /// Bank name inside "Connection to {name} may need attention".
  String? get attentionConnectionName {
    final name = _connectionAttention
        .firstMatch(message.trim())
        ?.group(1)
        ?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  factory fromJson(Map<String, dynamic> json) {
    return SimpleFinError(
      code: json['code'] as String? ?? 'gen.',
      message: json['msg'] as String? ?? 'Unknown error',
      connId: json['conn_id'] as String?,
      accountId: json['account_id'] as String?,
    );
  }
}

/// Unique banks whose credentials SimpleFIN asked us to fix.
class SimpleFinAuthConnections.fromErrors(List<SimpleFinError> errors) {
  final List<String> names = _uniqueNames(errors);

  bool get isEmpty => names.isEmpty;

  static List<String> _uniqueNames(List<SimpleFinError> errors) {
    final names = <String>[];
    final seen = <String>{};
    for (final error in errors) {
      if (!error.asksToReauthenticate) continue;
      final name = error.attentionConnectionName ?? error.message.trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
      names.add(name);
    }
    return names;
  }
}

class const SimpleFinConnection({
  required final String id,
  required final String name,
  final String? orgUrl,
}) {
  factory fromJson(Map<String, dynamic> json) {
    return SimpleFinConnection(
      id: json['conn_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      orgUrl: json['org_url'] as String?,
    );
  }
}

class const SimpleFinAccountSet({
  required final List<SimpleFinError> errors,
  required final List<SimpleFinAccount> accounts,
  final List<SimpleFinConnection> connections = const [],
});

class const SimpleFinAccount({
  required final String id,
  required final String name,
  required final String currency,
  required final String balance,
  final String? availableBalance,
  required final int balanceDate,
  final String? connId,
  final String? connName,
  required final List<SimpleFinTransaction> transactions,
}) {
  SimpleFinAccount copyWith({String? connName}) {
    return SimpleFinAccount(
      id: id,
      name: name,
      currency: currency,
      balance: balance,
      availableBalance: availableBalance,
      balanceDate: balanceDate,
      connId: connId,
      connName: connName ?? this.connName,
      transactions: transactions,
    );
  }
}

class const SimpleFinTransaction({
  required final String id,
  required final int posted,
  required final String amount,
  required final String description,
  required final bool pending,
});

class SimpleFinClaimException(final String message, {final int? statusCode})
    implements Exception {
  @override
  String toString() => message;
}

class SimpleFinFetchException(final String message, {final int? statusCode})
    implements Exception {
  @override
  String toString() => message;
}
