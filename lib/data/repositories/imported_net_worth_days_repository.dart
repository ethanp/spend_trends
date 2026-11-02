import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:spend_trends/domain/accounts/imported_net_worth_day.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';

/// Net worth days imported from Empower; loaded on the server, read-only here.
class ImportedNetWorthDaysRepository(final PowerSyncDatabase _powerSync) {
  /// Oldest first.
  Future<List<ImportedNetWorthDay>> listAll() async {
    final dayRows = await _powerSync.getAll(
      'SELECT recorded_on, net_worth_cents FROM imported_net_worth_days '
      'ORDER BY recorded_on',
    );
    return dayRows.map(_fromRow).toList();
  }

  static ImportedNetWorthDay _fromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    return ImportedNetWorthDay(
      day: CalendarDay.fromLocalMillis(columns['recorded_on'].asInt()),
      netWorthCents: columns['net_worth_cents'].asInt(),
    );
  }
}

final importedNetWorthDaysRepositoryProvider =
    FutureProvider<ImportedNetWorthDaysRepository>((ref) async {
      final database = await ref.watch(powerSyncDatabaseProvider.future);
      return ImportedNetWorthDaysRepository(database);
    });

/// Empower's daily net worth for the years before this app recorded balances.
final importedNetWorthDaysProvider = FutureProvider<List<ImportedNetWorthDay>>((
  ref,
) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(
    importedNetWorthDaysRepositoryProvider.future,
  );
  return repository.listAll();
});
