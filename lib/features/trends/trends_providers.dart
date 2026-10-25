import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/imported_net_worth_day.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/imported_net_worth_days_repository.dart';

import 'build_trends_charts.dart';
import 'trends_chart_bundle.dart';

/// Shared yr/mo/day display rate for every Trends chart and the three numbers.
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

final trendsChartBundleProvider = FutureProvider<TrendsChartBundle>((
  ref,
) async {
  final List<BankTransaction> transactions = await ref.watch(
    transactionsListProvider.future,
  );
  final List<SpendCategory> categories = await ref.watch(
    categoriesListProvider.future,
  );
  final List<CategoryGroup> groups = await ref.watch(
    categoryGroupsProvider.future,
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
  return const BuildTrendsCharts().build(
    transactions: transactions,
    categories: categories,
    groups: groups,
    accounts: accounts.values.toList(),
    ownedAssets: ownedAssets,
    balanceSnapshots: balanceSnapshots,
    importedNetWorthDays: importedNetWorthDays,
  );
});
