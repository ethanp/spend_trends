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
import 'package:spend_trends/features/trends/net_worth_trend.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/features/trends/trends_chart_bundle.dart';
import 'package:spend_trends/providers/spend_trends_providers.dart';
import 'package:spend_trends/widgets/sync_status_nav_button.dart';

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
        leading: SyncStatusNavButton(),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        bottom: false,
        child: trendsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ELayout.spaceLg),
              child: Text(
                '$error',
                style: EText.body.medium.copyWith(color: EColors.danger),
              ),
            ),
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
    required List<LifeEvent> lifeEvents,
    required StayChain? housingChain,
    required StayChain? jobChain,
  }) {
    if (bundle.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ELayout.spaceXl),
          child: Text(
            'Connect a bank on the Banks tab and sync, or import CSV in '
            'Settings, to see long-term trends.',
            style: EText.body.medium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(ELayout.spaceLg).withOverlaidTabBar(context),
      children: [
        if (bundle.categorySpend.isNotEmpty)
          CategoryTrendChart(
            title: 'Category spend',
            seriesList: bundle.categorySpend,
            transactions: transactions,
            categories: categories,
            groups: groups,
            lifeEvents: lifeEvents,
            housingChain: housingChain,
            jobChain: jobChain,
            showSpendRateToggle: true,
            useDistributionLegend: true,
          ),
        if (bundle.categorySpend.isNotEmpty && bundle.cashFlows.isNotEmpty)
          const SizedBox(height: ELayout.spaceLg),
        if (bundle.cashFlows.isNotEmpty)
          CategoryTrendChart(
            title: 'Income · Spending · Savings',
            subtitle: null,
            seriesList: bundle.cashFlows,
            transactions: transactions,
            categories: categories,
            groups: groups,
            lifeEvents: lifeEvents,
            housingChain: housingChain,
            jobChain: jobChain,
            showSpendRateToggle: bundle.categorySpend.isEmpty,
            initiallyHiddenSeriesIds: const {
              TrendChartCatalog.transferSeriesId,
            },
          ),
        if (bundle.netWorth.isNotEmpty) ...[
          if (bundle.categorySpend.isNotEmpty || bundle.cashFlows.isNotEmpty)
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
            lifeEvents: lifeEvents,
            housingChain: housingChain,
            jobChain: jobChain,
            valueKind: TrendValueKind.level,
            enableContributors: false,
          ),
        ],
      ],
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
