import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

class AccountsRepository(final PowerSyncDatabase _powerSync) {
  Future<List<Account>> listAccounts() async {
    final rows = await _powerSync.getAll(
      'SELECT * FROM accounts ORDER BY name COLLATE NOCASE',
    );
    final accounts = rows.map(_fromRow).toList();
    accounts.sort(
      (left, right) => left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      ),
    );
    return accounts;
  }

  Future<Account?> findByExternalId(String externalId) async {
    final row = await _powerSync.getOptional(
      'SELECT * FROM accounts WHERE external_id = ? LIMIT 1',
      [externalId],
    );
    if (row == null) return null;
    return _fromRow(row);
  }

  Future<Account?> findById(String accountId) async {
    final row = await _powerSync.getOptional(
      'SELECT * FROM accounts WHERE id = ? LIMIT 1',
      [accountId],
    );
    if (row == null) return null;
    return _fromRow(row);
  }

  Future<void> upsertAccount(Account account) async {
    final existing = await findByExternalId(account.externalId);
    final id = existing?.id ?? account.id;
    await _powerSync.upsert('accounts', {
      'id': id,
      'external_id': account.externalId,
      'name': account.name,
      'currency': account.currency,
      'balance_cents': account.balanceCents,
      'balance_as_of': account.balanceAsOf?.millisecondsSinceEpoch,
      'conn_id': account.connId,
      'conn_name': account.connName,
      'last_synced_at': account.lastSyncedAt?.millisecondsSinceEpoch,
      'status': account.status.storageValue,
      'status_message': account.statusMessage,
      'user_label': account.userLabel,
      'conn_user_label': account.connUserLabel,
      'account_kind': account.kind.storageValue,
      'belongs_to_account_id':
          account.belongsToAccountId ?? existing?.belongsToAccountId,
    });
  }

  /// Sets or clears the user-visible label. Empty/whitespace clears to official name.
  Future<void> updateUserLabel({
    required String accountId,
    required String? userLabel,
  }) async {
    final trimmed = userLabel?.trim();
    final stored = trimmed == null || trimmed.isEmpty ? null : trimmed;
    await _powerSync.execute(
      'UPDATE accounts SET user_label = ? WHERE id = ?',
      [stored, accountId],
    );
  }

  /// Sets or clears the bank/institution label for every account in that bank.
  Future<void> updateInstitutionUserLabel({
    required Account account,
    required String? connUserLabel,
  }) async {
    if (account.isCopilot) {
      throw StateError('Copilot has no editable institution label.');
    }
    final trimmed = connUserLabel?.trim();
    final stored = trimmed == null || trimmed.isEmpty ? null : trimmed;
    final connId = account.connId?.trim();
    if (connId != null && connId.isNotEmpty) {
      await _powerSync.execute(
        'UPDATE accounts SET conn_user_label = ? WHERE conn_id = ?',
        [stored, connId],
      );
      return;
    }
    final connName = account.connName?.trim();
    if (connName == null || connName.isEmpty) {
      throw StateError('Account has no institution to rename.');
    }
    await _powerSync.execute(
      '''
UPDATE accounts
SET conn_user_label = ?
WHERE conn_name = ?
  AND (conn_id IS NULL OR conn_id = '')
''',
      [stored, connName],
    );
  }

  Future<void> updateKind({
    required String accountId,
    required AccountKind kind,
  }) async {
    await _powerSync.execute(
      'UPDATE accounts SET account_kind = ? WHERE id = ?',
      [kind.storageValue, accountId],
    );
  }

  /// Marks [accountId] as a prior/history account of [belongsToAccountId],
  /// or clears the link.
  Future<void> updateBelongsTo({
    required String accountId,
    required String? belongsToAccountId,
  }) async {
    final child = await findById(accountId);
    if (child == null) {
      throw StateError('Account $accountId not found.');
    }

    if (belongsToAccountId != null) {
      if (belongsToAccountId == accountId) {
        throw ArgumentError('An account cannot belong to itself.');
      }
      final parent = await findById(belongsToAccountId);
      if (parent == null) {
        throw StateError('Parent account $belongsToAccountId not found.');
      }
      if (parent.isCopilot) {
        throw StateError('Parent must not be a Copilot account.');
      }
      if (parent.hasParent) {
        throw StateError('Parent cannot already be a prior account.');
      }
      final dependent = await _powerSync.getOptional(
        'SELECT id FROM accounts WHERE belongs_to_account_id = ? LIMIT 1',
        [accountId],
      );
      if (dependent != null) {
        throw StateError('Cannot nest a prior account under another.');
      }
    }

    await _powerSync.execute(
      'UPDATE accounts SET belongs_to_account_id = ? WHERE id = ?',
      [belongsToAccountId, accountId],
    );
  }

  Future<void> deleteAll() async {
    await _powerSync.execute('DELETE FROM transactions');
    await _powerSync.execute('DELETE FROM accounts');
  }

  static Account _fromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    final draft = Account(
      id: columns['id'] as String,
      externalId: columns['external_id'] as String,
      name: columns['name'] as String,
      currency: columns['currency'] as String,
      balanceCents: columns['balance_cents'].asInt(),
      balanceAsOf: columns['balance_as_of'].asIntOrNull().dateTimeFromMillis,
      connId: columns['conn_id'] as String?,
      connName: columns['conn_name'] as String?,
      lastSyncedAt: columns['last_synced_at'].asIntOrNull().dateTimeFromMillis,
      status: AccountStatus.fromStorage(columns['status'] as String),
      statusMessage: columns['status_message'] as String?,
      userLabel: columns['user_label'] as String?,
      connUserLabel: columns['conn_user_label'] as String?,
      belongsToAccountId: columns['belongs_to_account_id'] as String?,
    );
    final storedKind = AccountKind.tryFromStorage(
      columns['account_kind'] as String?,
    );
    return draft.copyWith(
      kind: storedKind ?? AccountKindClassifier.classify(draft),
    );
  }
}

final accountsRepositoryProvider = FutureProvider<AccountsRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return AccountsRepository(database);
});
