import 'dart:isolate';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_balance_snapshot.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/accounts/imported_net_worth_day.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/accounts/owned_asset.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/domain/trends/trend_spend_rate.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/data/repositories/account_balance_snapshots_repository.dart';
import 'package:spend_trends/data/repositories/categories_repository.dart';
import 'package:spend_trends/data/repositories/life_events_repository.dart';
import 'package:spend_trends/data/repositories/owned_assets_repository.dart';
import 'package:spend_trends/data/repositories/imported_net_worth_days_repository.dart';

import 'build_trends_charts.dart';

import 'package:spend_trends/domain/categories/conscious_spending_numbers.dart';

import 'trends_chart_bundle.dart';

const _log = ELogger('Trends');

/// Shared yr/mo/day display rate for every Trends pace chart and its
/// contributors.
final trendSpendRateProvider =
    NotifierProvider<TrendSpendRateNotifier, TrendSpendRate>(
      TrendSpendRateNotifier.new,
    );

class TrendSpendRateNotifier() extends Notifier<TrendSpendRate> {
  @override
  TrendSpendRate build() => TrendSpendRate.perYear;

  void setRate(TrendSpendRate rate) => state = rate;
}

/// Shared date window for every Trends chart. Null shows each chart's whole history.
final trendVisibleRangeProvider =
    NotifierProvider<TrendVisibleRangeNotifier, EChartVisibleRange?>(
      TrendVisibleRangeNotifier.new,
    );

class TrendVisibleRangeNotifier() extends Notifier<EChartVisibleRange?> {
  @override
  EChartVisibleRange? build() => null;

  void setVisibleRange(EChartVisibleRange visibleRange) => state = visibleRange;
}

/// The three numbers, apart from the charts so the card fills in as soon as
/// its own inputs load. Runs on another isolate: it scans every transaction.
final consciousSpendingNumbersProvider =
    FutureProvider<ConsciousSpendingNumbers>((ref) async {
      final List<BankTransaction> transactions = await ref.watch(
        transactionsListProvider.future,
      );
      final List<SpendCategory> categories = await ref.watch(
        categoriesListProvider.future,
      );
      final List<Account> accounts = (await ref.watch(
        accountsMapProvider.future,
      )).values.toList();
      final List<AccountBalanceSnapshot> balanceSnapshots = await ref.watch(
        accountBalanceSnapshotsProvider.future,
      );
      final List<LifeEvent> lifeEvents = await ref.watch(
        lifeEventsProvider.future,
      );
      return Isolate.run(
        () => ConsciousSpendingNumbers.endingOn(
          transactions: transactions,
          categories: categories,
          accounts: accounts,
          balanceSnapshots: balanceSnapshots,
          lifeEvents: lifeEvents,
          today: DateTime.now(),
        ),
      );
    });

/// Every Trends chart from the live tables. The series math scans every
/// transaction against a three-year kernel, so it runs on another isolate;
/// each chart card holds its place until it lands.
final trendsChartBundleProvider = FutureProvider<TrendsChartBundle>((
  ref,
) async {
  final stopwatch = Stopwatch()..start();
  final List<BankTransaction> transactions = await ref.watch(
    transactionsListProvider.future,
  );
  final List<SpendCategory> categories = await ref.watch(
    categoriesListProvider.future,
  );
  final Map<String, Account> accounts = await ref.watch(
    accountsMapProvider.future,
  );
  final List<OwnedAssetWithValuations> ownedAssets = await ref.watch(
    ownedAssetsListProvider.future,
  );
  final List<AccountBalanceSnapshot> balanceSnapshots = await ref.watch(
    accountBalanceSnapshotsProvider.future,
  );
  final List<ImportedNetWorthDay> importedNetWorthDays = await ref.watch(
    importedNetWorthDaysProvider.future,
  );
  final int inputsLoadedMs = stopwatch.elapsedMilliseconds;
  final List<Account> accountList = accounts.values.toList();
  final TrendsChartBundle bundle = await Isolate.run(
    () => const BuildTrendsCharts().build(
      transactions: transactions,
      categories: categories,
      accounts: accountList,
      ownedAssets: ownedAssets,
      balanceSnapshots: balanceSnapshots,
      importedNetWorthDays: importedNetWorthDays,
    ),
  );
  _log.log(
    'Chart bundle from ${transactions.length} transactions: inputs loaded in '
    '${inputsLoadedMs}ms, series built in '
    '${stopwatch.elapsedMilliseconds - inputsLoadedMs}ms '
    '(${bundle.phaseSummary})',
  );
  return bundle;
});
