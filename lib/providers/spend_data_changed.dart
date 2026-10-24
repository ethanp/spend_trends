import 'dart:async';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-wide spend-data invalidation bus.
///
/// Incremented by activity, banks, categories, life_chains, life_events,
/// owned_assets, and settings after writes.
final spendDataChangedProvider = NotifierProvider<SpendDataChanged, int>(
  SpendDataChanged.new,
);

class SpendDataChanged() extends Notifier<int> {
  static const _coalesceWindow = Duration(milliseconds: 200);

  Timer? _coalesceTimer;

  @override
  int build() {
    ref.onDispose(() => _coalesceTimer?.cancel());
    ref.listen(localDataRevisionProvider, (_, _) {
      _scheduleCoalescedBump();
    });
    return 0;
  }

  void notify() => _scheduleCoalescedBump();

  /// One invalidation after a burst of writes (manual notify + PowerSync onChange).
  void _scheduleCoalescedBump() {
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(_coalesceWindow, () {
      _coalesceTimer = null;
      state = state + 1;
    });
  }
}
