import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';

import 'build_trends_charts.dart';
import 'trends_chart_bundle.dart';

/// Shared yr/mo/day display rate for both Trends charts.
final trendSpendRateProvider =
    NotifierProvider<TrendSpendRateNotifier, TrendSpendRate>(
      TrendSpendRateNotifier.new,
    );

class TrendSpendRateNotifier() extends Notifier<TrendSpendRate> {
  @override
  TrendSpendRate build() => TrendSpendRate.perYear;

  void setRate(TrendSpendRate rate) => state = rate;
}

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
  return const BuildTrendsCharts().build(
    transactions: transactions,
    categories: categories,
    groups: groups,
    accounts: accounts.values.toList(),
    ownedAssets: ownedAssets,
  );
});
