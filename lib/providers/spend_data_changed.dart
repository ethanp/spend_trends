import 'dart:async';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

const _log = ELogger('SpendDataChanged');

/// App-wide spend-data invalidation bus.
///
/// Incremented by activity, banks, categories, life_chains, life_events,
/// owned_assets, and settings after writes, and by any local or synced
/// change to a spend-data table.
final spendDataChangedProvider = NotifierProvider<SpendDataChanged, int>(
  SpendDataChanged.new,
);

class SpendDataChanged() extends Notifier<int> {
  static const _coalesceWindow = Duration(milliseconds: 200);
  static const _changeThrottle = Duration(milliseconds: 120);

  /// Projection assumptions are not spend data: the projection follows its
  /// own row, and a slider release must not reload every transaction.
  static const _tablesOutsideSpendData = {'projection_settings'};

  Timer? _coalesceTimer;

  @override
  int build() {
    ref.onDispose(() => _coalesceTimer?.cancel());
    final PowerSyncDatabase? database = ref
        .watch(powerSyncDatabaseProvider)
        .value;
    if (database == null) return 0;
    // Only later changes invalidate: the data providers already read the
    // database as it opened.
    final subscription = database
        .onChange(
          [
            for (final table in database.schema.tables)
              if (!_tablesOutsideSpendData.contains(table.name)) table.name,
          ],
          throttle: _changeThrottle,
          triggerImmediately: false,
        )
        .listen((change) => _scheduleCoalescedBump());
    ref.onDispose(subscription.cancel);
    return 0;
  }

  void notify() => _scheduleCoalescedBump();

  /// One invalidation after a burst of writes (manual notify + PowerSync onChange).
  void _scheduleCoalescedBump() {
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(_coalesceWindow, () {
      _coalesceTimer = null;
      state = state + 1;
      _log.log('Spend data changed (revision $state)');
    });
  }
}
