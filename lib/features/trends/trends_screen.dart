import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/features/projections/fire_outlook_card.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/trends/category_trend_chart.dart';
import 'package:spend_trends/features/trends/centered_moving_average.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers_card.dart';
import 'package:spend_trends/features/trends/net_worth_trend.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/features/trends/trend_range_scrubber.dart';
import 'package:spend_trends/features/trends/trends_chart_bundle.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/life_events/life_events_providers.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';

import 'trends_providers.dart';

class const TrendsScreen() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Trends',
        leading: ESyncPhaseIcon(),
        automaticallyImplyLeading: false,
        actions: [FireOutlookCard()],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: ETabBarOverlay.paddingOf(context),
          children: [_consciousSpendingNumbers(ref), ..._charts(ref)],
        ),
      ),
    );
  }

  /// Each section fills in when its own provider lands; a reload keeps the
  /// previous numbers on screen.
  Widget _consciousSpendingNumbers(WidgetRef ref) {
    final AsyncValue<ConsciousSpendingNumbers> numbersAsync = ref.watch(
      consciousSpendingNumbersProvider,
    );
    if (numbersAsync.hasError && !numbersAsync.hasValue) {
      return ELoadErrorView(
        screenName: 'Three numbers',
        error: numbersAsync.error!,
        stackTrace: numbersAsync.stackTrace,
      );
    }
    return ConsciousSpendingNumbersCard(
      consciousSpendingNumbers: numbersAsync.value,
    );
  }

  List<Widget> _charts(WidgetRef ref) {
    final AsyncValue<TrendsChartBundle> trendsAsync = ref.watch(
      trendsChartBundleProvider,
    );
    if (trendsAsync.hasError && !trendsAsync.hasValue) {
      return [
        const SizedBox(height: ELayout.spaceLg),
        ELoadErrorView(
          screenName: 'Trends',
          error: trendsAsync.error!,
          stackTrace: trendsAsync.stackTrace,
        ),
      ];
    }
    final TrendsChartBundle? bundle = trendsAsync.value;
    if (bundle != null && bundle.isEmpty) {
      return [
        const SizedBox(height: ELayout.spaceXl),
        Text(
          'Connect a bank on the Banks tab and sync, or import CSV in '
          'Settings, to see long-term trends.',
          style: EText.body.medium,
          textAlign: TextAlign.center,
        ),
      ];
    }
    final _ChartContext chartContext = _ChartContext.watch(ref);
    return [
      if (bundle == null || bundle.cashFlows.isNotEmpty) ...[
        const SizedBox(height: ELayout.spaceLg),
        _cashFlowChart(bundle, chartContext),
      ],
      if (bundle == null || bundle.netWorth.isNotEmpty) ...[
        const SizedBox(height: ELayout.spaceLg),
        _netWorthChart(bundle, chartContext, ref),
      ],
      if (bundle == null || bundle.categorySpend.isNotEmpty) ...[
        const SizedBox(height: ELayout.spaceLg),
        _categorySpendChart(bundle, chartContext),
      ],
    ];
  }

  Widget _cashFlowChart(TrendsChartBundle? bundle, _ChartContext chartContext) {
    return CategoryTrendChart(
      title: 'Income · Spending · Savings',
      subtitle: null,
      seriesList: bundle?.cashFlows ?? const [],
      seriesStillComputing: bundle == null,
      transactions: chartContext.transactions,
      categories: chartContext.categories,
      groups: chartContext.groups,
      accounts: chartContext.accounts,
      lifeEvents: chartContext.lifeEvents,
      initiallyHiddenSeriesIds: const {TrendChartCatalog.transferSeriesId},
      rangeScrubber: bundle == null ? null : _rangeScrubber(bundle),
    );
  }

  Widget _netWorthChart(
    TrendsChartBundle? bundle,
    _ChartContext chartContext,
    WidgetRef ref,
  ) {
    return CategoryTrendChart(
      title: 'Net worth',
      headlineFigures: _netWorthHeadlines(
        currentCents: _sumNetWorthCents(
          ref.watch(accountsMapProvider),
          ref.watch(ownedAssetsListProvider),
        ),
        netWorthSeries: bundle?.netWorth ?? const [],
      ),
      subtitle:
          'Accounts plus owned assets. The line averages '
          '±${CenteredMovingAverage.standard.halfWindowDays ~/ 7} weeks; '
          'debts plot above zero as dashed lines.',
      seriesList: bundle?.netWorth ?? const [],
      seriesStillComputing: bundle == null,
      transactions: chartContext.transactions,
      categories: chartContext.categories,
      groups: chartContext.groups,
      accounts: chartContext.accounts,
      lifeEvents: chartContext.lifeEvents,
      valueKind: TrendValueKind.level,
      enableContributors: false,
    );
  }

  Widget _categorySpendChart(
    TrendsChartBundle? bundle,
    _ChartContext chartContext,
  ) {
    return CategoryTrendChart(
      title: 'Category spend',
      seriesList: bundle?.categorySpend ?? const [],
      seriesStillComputing: bundle == null,
      transactions: chartContext.transactions,
      categories: chartContext.categories,
      groups: chartContext.groups,
      accounts: chartContext.accounts,
      lifeEvents: chartContext.lifeEvents,
      useDistributionLegend: true,
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

/// What every chart's contributors sheet and event markers read; each list is
/// empty until its own provider loads.
class const _ChartContext({
  required final List<BankTransaction> transactions,
  required final List<SpendCategory> categories,
  required final List<CategoryGroup> groups,
  required final List<Account> accounts,
  required final List<LifeEvent> lifeEvents,
}) {
  factory watch(WidgetRef ref) => _ChartContext(
    transactions: ref.watch(transactionsListProvider).value ?? const [],
    categories: ref.watch(categoriesListProvider).value ?? const [],
    groups: ref.watch(categoryGroupsProvider).value ?? const [],
    accounts: ref.watch(accountsMapProvider).value?.values.toList() ?? const [],
    lifeEvents: ref.watch(lifeEventsProvider).value ?? const [],
  );
}
