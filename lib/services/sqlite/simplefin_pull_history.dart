import 'dart:convert';

import 'package:spend_trends/services/simplefin/simplefin_models.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

/// Kind of SimpleFIN account fetch for one pull run.
enum SimpleFinPullKind({required final String displayLabel}) {
  full(displayLabel: 'Full history'),
  incremental(displayLabel: 'Incremental');

  String get storageValue => name;

  static SimpleFinPullKind fromStorage(String value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return SimpleFinPullKind.incremental;
  }
}

/// Outcome of a SimpleFIN pull row in [simplefin_pulls].
enum SimpleFinPullStatus() {
  running,
  success,
  failed;

  String get storageValue => name;

  static SimpleFinPullStatus fromStorage(String value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return SimpleFinPullStatus.failed;
  }
}

/// Per-account outcome within a pull.
enum SimpleFinPullAccountStatus({
  required final String storageValue,
  required final String displayLabel,
  required final int severityRank,
}) {
  ok(storageValue: 'ok', displayLabel: 'OK', severityRank: 0),
  needsRelink(
    storageValue: 'needs_relink',
    displayLabel: 'Needs re-link',
    severityRank: 1,
  ),
  error(storageValue: 'error', displayLabel: 'Error', severityRank: 2);

  bool get isIssue => this != SimpleFinPullAccountStatus.ok;

  static SimpleFinPullAccountStatus fromStorage(String value) {
    return switch (value) {
      'needs_relink' => SimpleFinPullAccountStatus.needsRelink,
      'error' => SimpleFinPullAccountStatus.error,
      _ => SimpleFinPullAccountStatus.ok,
    };
  }
}

/// One account's outcome for a pull (write + read).
class const SimpleFinPullAccountRecord({
  required final String id,
  required final String pullId,
  final String? accountId,
  final String? accountExternalId,
  final String? connId,
  required final String accountLabel,
  required final int transactionCount,
  required final SimpleFinPullAccountStatus status,
  final String? errorMessage,
});

/// One SimpleFIN pull run with optional per-account outcomes.
class const SimpleFinPullRecord({
  required final String id,
  required final SimpleFinPullKind kind,
  required final SimpleFinPullStatus status,
  required final DateTime startedAt,
  final DateTime? finishedAt,
  final int? accountCount,
  final int? transactionCount,
  final List<SimpleFinError> errors = const [],
  final List<SimpleFinPullAccountRecord> accounts = const [],
}) {
  Duration? get duration {
    final end = finishedAt;
    if (end == null) return null;
    return end.difference(startedAt);
  }

  int get issueAccountCount =>
      accounts.where((account) => account.status.isIssue).length;

  bool get hasAccountIssues => issueAccountCount > 0;

  bool get isPartialSuccess =>
      status == SimpleFinPullStatus.success && hasAccountIssues;
}

/// Draft used while a pull is in progress before persist.
class SimpleFinPullAccountDraft({
  var String? accountId,
  var String? accountExternalId,
  var String? connId,
  required var String accountLabel,
  var int transactionCount = 0,
  var SimpleFinPullAccountStatus status = SimpleFinPullAccountStatus.ok,
  var String? errorMessage,
}) {
  void addTransactions(int count) {
    transactionCount += count;
  }

  void mergeStatus(SimpleFinPullAccountStatus next, String? message) {
    if (next.severityRank < status.severityRank) {
      return;
    }
    status = next;
    if (message != null && message.isNotEmpty) {
      errorMessage = message;
    }
  }
}

/// Append-only log of SimpleFIN pulls. Incremental watermark is the latest
/// successful [finished_at] — full-history runs never erase prior successes.
class SimpleFinPullHistory(final PowerSyncDatabase _powerSync) {
  final _uuid = const Uuid();

  static const _legacyLastSuccessfulPullKey = 'last_successful_pull_at';
  static const _legacyLastErrlistKey = 'last_errlist_json';

  Future<DateTime?> lastSuccessfulPullAt() async {
    final row = await _powerSync.getOptional(
      '''
      SELECT finished_at FROM simplefin_pulls
      WHERE status = ?
      ORDER BY finished_at DESC
      LIMIT 1
      ''',
      [SimpleFinPullStatus.success.storageValue],
    );
    if (row != null) {
      final millis = row['finished_at'] as int?;
      if (millis != null) {
        return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      }
    }
    return _migrateLegacyWatermark();
  }

  Future<List<SimpleFinPullRecord>> listRecent({int limit = 30}) async {
    final pullRows = await _powerSync.getAll(
      '''
      SELECT * FROM simplefin_pulls
      ORDER BY started_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    if (pullRows.isEmpty) return const [];

    final pullIds = [for (final row in pullRows) row['id'] as String];
    final placeholders = List.filled(pullIds.length, '?').join(', ');
    final accountRows = await _powerSync.getAll('''
      SELECT * FROM simplefin_pull_accounts
      WHERE pull_id IN ($placeholders)
      ''', pullIds);
    final accountsByPullId = <String, List<SimpleFinPullAccountRecord>>{};
    for (final row in accountRows) {
      final record = _accountFromRow(row);
      accountsByPullId.putIfAbsent(record.pullId, () => []).add(record);
    }

    return [
      for (final row in pullRows)
        _pullFromRow(row, accountsByPullId[row['id'] as String] ?? const []),
    ];
  }

  Future<SimpleFinPullRecord?> latestFinished() async {
    final row = await _powerSync.getOptional(
      '''
      SELECT * FROM simplefin_pulls
      WHERE status IN (?, ?)
      ORDER BY finished_at DESC
      LIMIT 1
      ''',
      [
        SimpleFinPullStatus.success.storageValue,
        SimpleFinPullStatus.failed.storageValue,
      ],
    );
    if (row == null) return null;
    return _pullFromRow(row, await _accountsForPull(row['id'] as String));
  }

  Future<SimpleFinPullRecord?> latestRunning() async {
    final row = await _powerSync.getOptional(
      '''
      SELECT * FROM simplefin_pulls
      WHERE status = ?
      ORDER BY started_at DESC
      LIMIT 1
      ''',
      [SimpleFinPullStatus.running.storageValue],
    );
    if (row == null) return null;
    return _pullFromRow(row, await _accountsForPull(row['id'] as String));
  }

  /// Inserts a `running` row and returns its id.
  Future<String> beginPull({
    required SimpleFinPullKind kind,
    required DateTime startedAt,
  }) async {
    await _abandonStaleRunningPulls(startedAt);
    final pullId = _uuid.v4();
    await _powerSync.upsert('simplefin_pulls', {
      'id': pullId,
      'started_at': startedAt.toUtc().millisecondsSinceEpoch,
      'finished_at': null,
      'kind': kind.storageValue,
      'status': SimpleFinPullStatus.running.storageValue,
      'account_count': null,
      'transaction_count': null,
      'errors_json': null,
    });
    return pullId;
  }

  Future<void> finishPullSuccess({
    required String pullId,
    required DateTime finishedAt,
    required int accountCount,
    required int transactionCount,
    required List<SimpleFinError> errors,
    List<SimpleFinPullAccountDraft> accounts = const [],
  }) async {
    await _powerSync.upsert('simplefin_pulls', {
      'id': pullId,
      'finished_at': finishedAt.toUtc().millisecondsSinceEpoch,
      'status': SimpleFinPullStatus.success.storageValue,
      'account_count': accountCount,
      'transaction_count': transactionCount,
      'errors_json': _encodeErrors(errors),
    });
    await _insertAccountRows(pullId, accounts);
    await _clearLegacyKeys();
  }

  Future<void> finishPullFailed({
    required String pullId,
    required DateTime finishedAt,
    required String message,
    List<SimpleFinPullAccountDraft> accounts = const [],
  }) async {
    await _powerSync.upsert('simplefin_pulls', {
      'id': pullId,
      'finished_at': finishedAt.toUtc().millisecondsSinceEpoch,
      'status': SimpleFinPullStatus.failed.storageValue,
      'errors_json': jsonEncode([
        {'code': 'pull_failed', 'msg': message},
      ]),
    });
    await _insertAccountRows(pullId, accounts);
  }

  /// Errors from the latest finished pull (success or failed).
  Future<List<SimpleFinError>> lastErrors() async {
    final latest = await latestFinished();
    if (latest != null) return latest.errors;
    return _legacyErrors();
  }

  Future<void> clear() async {
    await _powerSync.execute('DELETE FROM simplefin_pull_accounts');
    await _powerSync.execute('DELETE FROM simplefin_pulls');
    await _powerSync.execute('DELETE FROM sync_state');
  }

  Future<void> _insertAccountRows(
    String pullId,
    List<SimpleFinPullAccountDraft> accounts,
  ) async {
    for (final draft in accounts) {
      await _powerSync.upsert('simplefin_pull_accounts', {
        'id': _uuid.v4(),
        'pull_id': pullId,
        'account_id': draft.accountId,
        'account_external_id': draft.accountExternalId,
        'conn_id': draft.connId,
        'account_label': draft.accountLabel,
        'transaction_count': draft.transactionCount,
        'status': draft.status.storageValue,
        'error_message': draft.errorMessage,
      });
    }
  }

  Future<List<SimpleFinPullAccountRecord>> _accountsForPull(
    String pullId,
  ) async {
    final rows = await _powerSync.getAll(
      'SELECT * FROM simplefin_pull_accounts WHERE pull_id = ?',
      [pullId],
    );
    return [for (final row in rows) _accountFromRow(row)];
  }

  SimpleFinPullRecord _pullFromRow(
    Map<String, dynamic> row,
    List<SimpleFinPullAccountRecord> accounts,
  ) {
    final startedMillis = row['started_at'] as int;
    final finishedMillis = row['finished_at'] as int?;
    return SimpleFinPullRecord(
      id: row['id'] as String,
      kind: SimpleFinPullKind.fromStorage(row['kind'] as String? ?? ''),
      status: SimpleFinPullStatus.fromStorage(row['status'] as String? ?? ''),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        startedMillis,
        isUtc: true,
      ),
      finishedAt: finishedMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(finishedMillis, isUtc: true),
      accountCount: row['account_count'] as int?,
      transactionCount: row['transaction_count'] as int?,
      errors: _decodeErrors(row['errors_json'] as String?),
      accounts: accounts,
    );
  }

  SimpleFinPullAccountRecord _accountFromRow(Map<String, dynamic> row) {
    return SimpleFinPullAccountRecord(
      id: row['id'] as String,
      pullId: row['pull_id'] as String,
      accountId: row['account_id'] as String?,
      accountExternalId: row['account_external_id'] as String?,
      connId: row['conn_id'] as String?,
      accountLabel: row['account_label'] as String? ?? '',
      transactionCount: row['transaction_count'] as int? ?? 0,
      status: SimpleFinPullAccountStatus.fromStorage(
        row['status'] as String? ?? 'ok',
      ),
      errorMessage: row['error_message'] as String?,
    );
  }

  Future<void> _abandonStaleRunningPulls(DateTime now) async {
    await _powerSync.execute(
      '''
      UPDATE simplefin_pulls
      SET status = ?, finished_at = ?
      WHERE status = ?
      ''',
      [
        SimpleFinPullStatus.failed.storageValue,
        now.toUtc().millisecondsSinceEpoch,
        SimpleFinPullStatus.running.storageValue,
      ],
    );
  }

  Future<DateTime?> _migrateLegacyWatermark() async {
    final value = await _readSyncState(_legacyLastSuccessfulPullKey);
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;

    final pullId = _uuid.v4();
    final finishedMillis = parsed.toUtc().millisecondsSinceEpoch;
    await _powerSync.upsert('simplefin_pulls', {
      'id': pullId,
      'started_at': finishedMillis,
      'finished_at': finishedMillis,
      'kind': SimpleFinPullKind.incremental.storageValue,
      'status': SimpleFinPullStatus.success.storageValue,
      'account_count': null,
      'transaction_count': null,
      'errors_json': await _readSyncState(_legacyLastErrlistKey),
    });
    await _clearLegacyKeys();
    return parsed.toUtc();
  }

  Future<List<SimpleFinError>> _legacyErrors() async {
    return _decodeErrors(await _readSyncState(_legacyLastErrlistKey));
  }

  Future<void> _clearLegacyKeys() async {
    await _powerSync.execute('DELETE FROM sync_state WHERE key IN (?, ?)', [
      _legacyLastSuccessfulPullKey,
      _legacyLastErrlistKey,
    ]);
  }

  Future<String?> _readSyncState(String key) async {
    final row = await _powerSync.getOptional(
      'SELECT value FROM sync_state WHERE key = ? LIMIT 1',
      [key],
    );
    if (row == null) return null;
    return row['value'] as String?;
  }

  static String _encodeErrors(List<SimpleFinError> errors) {
    return jsonEncode(
      errors
          .map(
            (error) => {
              'code': error.code,
              'msg': error.message,
              if (error.connId != null) 'conn_id': error.connId,
              if (error.accountId != null) 'account_id': error.accountId,
            },
          )
          .toList(),
    );
  }

  static List<SimpleFinError> _decodeErrors(String? value) {
    if (value == null || value.isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SimpleFinError.fromJson)
        .toList();
  }
}

final simpleFinPullHistoryProvider = FutureProvider<SimpleFinPullHistory>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return SimpleFinPullHistory(database);
});
