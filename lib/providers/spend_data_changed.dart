import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-wide spend-data invalidation bus.
///
/// Incremented by activity, banks, categories, life_chains, life_events,
/// owned_assets, and settings after writes.
final spendDataChangedProvider = NotifierProvider<SpendDataChanged, int>(
  SpendDataChanged.new,
);

class SpendDataChanged() extends Notifier<int> {
  @override
  int build() => 0;

  void notify() => state = state + 1;
}
