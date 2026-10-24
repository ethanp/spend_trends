import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';

/// Recorded balances for manual accounts.
class AccountBalanceSnapshotsRepository(final PowerSyncDatabase _powerSync) {
  /// Oldest first.
  Future<List<AccountBalanceSnapshot>> listAll() async {
    final rows = await _powerSync.getAll(
      'SELECT * FROM account_balance_snapshots ORDER BY recorded_on, id',
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> insert(AccountBalanceSnapshot snapshot) async {
    await _powerSync.execute(
      '''
      INSERT INTO account_balance_snapshots
        (id, account_id, balance_cents, recorded_on)
      VALUES (?, ?, ?, ?)
      ''',
      [
        snapshot.id,
        snapshot.accountId,
        snapshot.balanceCents,
        snapshot.recordedOn.startOfDay.millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> delete(String snapshotId) async {
    await _powerSync.execute(
      'DELETE FROM account_balance_snapshots WHERE id = ?',
      [snapshotId],
    );
  }

  static AccountBalanceSnapshot _fromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    return AccountBalanceSnapshot(
      id: columns['id'] as String,
      accountId: columns['account_id'] as String,
      balanceCents: columns['balance_cents'].asInt(),
      recordedOn: columns['recorded_on'].asInt().dateTimeFromMillis,
    );
  }
}

final accountBalanceSnapshotsRepositoryProvider =
    FutureProvider<AccountBalanceSnapshotsRepository>((ref) async {
      final database = await ref.watch(powerSyncDatabaseProvider.future);
      return AccountBalanceSnapshotsRepository(database);
    });
