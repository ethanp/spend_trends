import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/trends/category_trend_chart.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers_card.dart';
import 'package:spend_trends/features/trends/net_worth_trend.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/features/trends/trend_range_scrubber.dart';
import 'package:spend_trends/features/trends/trend_spend_rate_toggle.dart';
import 'package:spend_trends/features/trends/trends_chart_bundle.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/life_chains/life_chain_providers.dart';
import 'package:spend_trends/features/life_events/life_events_providers.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';

import 'trends_providers.dart';

class const TrendsScreen() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendsAsync = ref.watch(trendsChartBundleProvider);
    final transactionsAsync = ref.watch(transactionsListProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final groupsAsync = ref.watch(categoryGroupsProvider);
    final lifeEventsAsync = ref.watch(lifeEventsProvider);
    final housingAsync = ref.watch(housingChainProvider);
    final jobAsync = ref.watch(jobChainProvider);
    final accountsAsync = ref.watch(accountsMapProvider);
    final ownedAssetsAsync = ref.watch(ownedAssetsListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Trends',
        leading: ESyncPhaseIcon(),
        automaticallyImplyLeading: false,
        actions: [TrendSpendRateToggle()],
      ),
      body: SafeArea(
        bottom: false,
        child: trendsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ELoadErrorView(
            screenName: 'Trends',
            error: error,
            stackTrace: stackTrace,
          ),
          data: (bundle) => _trendsBody(
            context,
            bundle,
            currentNetWorthCents: _sumNetWorthCents(
              accountsAsync,
              ownedAssetsAsync,
            ),
            transactions:
                transactionsAsync.asData?.value ?? const <BankTransaction>[],
            categories:
                categoriesAsync.asData?.value ?? const <SpendCategory>[],
            groups: groupsAsync.asData?.value ?? const <CategoryGroup>[],
            accounts:
                accountsAsync.asData?.value.values.toList() ??
                const <Account>[],
            lifeEvents: lifeEventsAsync.asData?.value ?? const <LifeEvent>[],
            housingChain: housingAsync.asData?.value,
            jobChain: jobAsync.asData?.value,
          ),
        ),
      ),
    );
  }

  Widget _trendsBody(
    BuildContext context,
    TrendsChartBundle bundle, {
    required int? currentNetWorthCents,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
    required List<CategoryGroup> groups,
    required List<Account> accounts,
    required List<LifeEvent> lifeEvents,
    required StayChain? housingChain,
    required StayChain? jobChain,
  }) {
    if (bundle.isEmpty) {
      return ListView(
        padding: ETabBarOverlay.paddingOf(context),
        children: [
          ConsciousSpendingNumbersCard(
            consciousSpendingNumbers: bundle.consciousSpendingNumbers,
          ),
          const SizedBox(height: ELayout.spaceXl),
          Text(
            'Connect a bank on the Banks tab and sync, or import CSV in '
            'Settings, to see long-term trends.',
            style: EText.body.medium,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView(
      padding: ETabBarOverlay.paddingOf(context),
      children: [
        ConsciousSpendingNumbersCard(
          consciousSpendingNumbers: bundle.consciousSpendingNumbers,
        ),
        if (bundle.cashFlows.isNotEmpty) ...[
          const SizedBox(height: ELayout.spaceLg),
          CategoryTrendChart(
            title: 'Income · Spending · Savings',
            subtitle: null,
            seriesList: bundle.cashFlows,
            transactions: transactions,
            categories: categories,
            groups: groups,
            accounts: accounts,
            lifeEvents: lifeEvents,
            housingChain: housingChain,
            jobChain: jobChain,
            initiallyHiddenSeriesIds: const {
              TrendChartCatalog.transferSeriesId,
            },
            rangeScrubber: _rangeScrubber(bundle),
          ),
        ],
        if (bundle.netWorth.isNotEmpty) ...[
          const SizedBox(height: ELayout.spaceLg),
          CategoryTrendChart(
            title: 'Net worth',
            headlineFigures: _netWorthHeadlines(
              currentCents: currentNetWorthCents,
              netWorthSeries: bundle.netWorth,
            ),
            subtitle:
                'Current = accounts + owned assets · Smoothed = chart line tip · '
                'grouped by account kind · |balance|, dashed = liability',
            seriesList: bundle.netWorth,
            transactions: transactions,
            categories: categories,
            groups: groups,
            accounts: accounts,
            lifeEvents: lifeEvents,
            housingChain: housingChain,
            jobChain: jobChain,
            valueKind: TrendValueKind.level,
            enableContributors: false,
          ),
        ],
        if (bundle.categorySpend.isNotEmpty) ...[
          const SizedBox(height: ELayout.spaceLg),
          CategoryTrendChart(
            title: 'Category spend',
            seriesList: bundle.categorySpend,
            transactions: transactions,
            categories: categories,
            groups: groups,
            accounts: accounts,
            lifeEvents: lifeEvents,
            housingChain: housingChain,
            jobChain: jobChain,
            useDistributionLegend: true,
          ),
        ],
      ],
    );
  }

  static Widget? _rangeScrubber(TrendsChartBundle bundle) {
    final DateTimeRange? chartedDateRange = bundle.chartedDateRange;
    if (chartedDateRange == null) return null;
    return TrendRangeScrubber(
      chartedDateRange: chartedDateRange,
      cashFlowLines: TrendRangeScrubber.cashFlowLinesFrom(bundle.cashFlows),
    );
  }

  static int? _sumNetWorthCents(
    AsyncValue<Map<String, Account>> accountsAsync,
    AsyncValue<List<OwnedAssetWithValuations>> ownedAssetsAsync,
  ) {
    final accounts = accountsAsync.asData?.value;
    final ownedAssets = ownedAssetsAsync.asData?.value;
    if (accounts == null || ownedAssets == null) return null;
    return NetWorthTrend.currentCents(
      accounts: accounts.values,
      ownedAssets: ownedAssets,
    );
  }

  static List<ChartHeadlineFigure> _netWorthHeadlines({
    required int? currentCents,
    required List<CategoryTrendSeries> netWorthSeries,
  }) {
    final figures = <ChartHeadlineFigure>[];
    if (currentCents != null) {
      figures.add(ChartHeadlineFigure(label: 'Current', cents: currentCents));
    }
    final smoothedCents = _smoothedNetWorthCents(netWorthSeries);
    if (smoothedCents != null) {
      figures.add(ChartHeadlineFigure(label: 'Smoothed', cents: smoothedCents));
    }
    return figures;
  }

  static int? _smoothedNetWorthCents(List<CategoryTrendSeries> netWorthSeries) {
    for (final series in netWorthSeries) {
      if (series.id != TrendChartCatalog.netWorthSeriesId) continue;
      if (series.points.isEmpty) return null;
      return series.latestSmoothedCents.round();
    }
    return null;
  }
}
