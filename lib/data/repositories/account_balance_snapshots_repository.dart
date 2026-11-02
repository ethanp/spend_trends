import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:spend_trends/domain/accounts/account_balance_snapshot.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';

const _log = ELogger('SnapshotsRepository');

/// Recorded balances: manual updates, one per SimpleFIN pull day, and
/// history imported from Empower.
class AccountBalanceSnapshotsRepository(final PowerSyncDatabase _powerSync) {
  /// Oldest first.
  Future<List<AccountBalanceSnapshot>> listAll() async {
    final stopwatch = Stopwatch()..start();
    final rows = await _powerSync.getAll(
      'SELECT * FROM account_balance_snapshots ORDER BY recorded_on, id',
    );
    final int queryMs = stopwatch.elapsedMilliseconds;
    final snapshots = rows.map(_fromRow).toList();
    _log.log(
      'listAll: query ${queryMs}ms, mapped ${rows.length} rows in '
      '${stopwatch.elapsedMilliseconds - queryMs}ms',
    );
    return snapshots;
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
        snapshot.recordedDay.localMidnightMillis,
      ],
    );
  }

  /// One snapshot per account per day: a later pull the same day replaces it.
  Future<void> recordDailyBalance({
    required String accountId,
    required int balanceCents,
    required DateTime day,
  }) async {
    final CalendarDay recordedDay = day.calendarDay;
    await _powerSync.upsert('account_balance_snapshots', {
      'id': '$accountId@${recordedDay.isoDate}',
      'account_id': accountId,
      'balance_cents': balanceCents,
      'recorded_on': recordedDay.localMidnightMillis,
    });
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
      recordedDay: CalendarDay.fromLocalMillis(columns['recorded_on'].asInt()),
    );
  }
}

final accountBalanceSnapshotsRepositoryProvider =
    FutureProvider<AccountBalanceSnapshotsRepository>((ref) async {
      final database = await ref.watch(powerSyncDatabaseProvider.future);
      return AccountBalanceSnapshotsRepository(database);
    });

/// Recorded account balances, oldest first.
final accountBalanceSnapshotsProvider =
    FutureProvider<List<AccountBalanceSnapshot>>((ref) async {
      ref.watch(spendDataChangedProvider);
      final repository = await ref.watch(
        accountBalanceSnapshotsRepositoryProvider.future,
      );
      return repository.listAll();
    });
