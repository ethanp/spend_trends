import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_balance_snapshot.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/category_group.dart';
import 'package:spend_trends/domain/accounts/imported_net_worth_day.dart';
import 'package:spend_trends/domain/accounts/owned_asset.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/ui/trends/cash_flow_trend_builder.dart';
import 'package:spend_trends/ui/trends/category_trend_series.dart';
import 'package:spend_trends/ui/trends/category_spend_trend_builder.dart';
import 'package:spend_trends/ui/trends/net_worth_trend.dart';
import 'package:spend_trends/ui/trends/trends_chart_bundle.dart';
import 'package:ethan_utils/ethan_utils.dart';

/// Builds Trends chart series from transactions, categories, and accounts.
class const BuildTrendsCharts() {
  TrendsChartBundle build({
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
    List<CategoryGroup> groups = const [],
    List<Account> accounts = const [],
    List<OwnedAssetWithValuations> ownedAssets = const [],
    List<AccountBalanceSnapshot> balanceSnapshots = const [],
    List<ImportedNetWorthDay> importedNetWorthDays = const [],
    DateTime? endDate,
  }) {
    final phaseStopwatch = Stopwatch()..start();
    final phaseMillis = <String, int>{};
    void endPhase(String name) {
      phaseMillis[name] = phaseStopwatch.elapsedMilliseconds;
      phaseStopwatch.reset();
    }

    final chartEnd = (endDate ?? DateTime.now()).startOfDay;
    final historyStart = BankTransaction.completeHistoryStart.startOfDay;
    final CalendarDay historyStartDay = historyStart.calendarDay;
    final inRangeTransactions = [
      for (final transaction in transactions)
        if (!transaction.postedDay.isBefore(historyStartDay)) transaction,
    ];

    final spendExcludedIds = {
      ...SpecialCategory.flowIds,
      for (final category in categories)
        if (category.isFlow) category.id,
    };
    final spendMaps = CategorySpendDailyMaps.fromTransactions(
      transactions: inRangeTransactions,
      flowCategoryIds: spendExcludedIds,
    );
    final cashFlowMaps = CashFlowDailyMaps.fromTransactions(
      inRangeTransactions,
      categories: categories,
      accounts: accounts,
    );

    endPhase('daily maps');
    final chartRange = _resolveChartRange(
      spendMaps: spendMaps,
      cashFlowMaps: cashFlowMaps,
      inRangeTransactions: inRangeTransactions,
      accounts: accounts,
      ownedAssets: ownedAssets,
      historyStart: historyStart,
      chartEnd: chartEnd,
    );
    if (chartRange == null) {
      return const TrendsChartBundle(categorySpend: [], cashFlows: []);
    }

    final hasSpendHistory = chartRange.hasSpendHistory;
    endPhase('chart range');
    final categorySpend = hasSpendHistory
        ? CategorySpendTrendBuilder(
            spendMaps: spendMaps,
            incomeByDay: cashFlowMaps.incomeByDay,
            categories: categories,
            groups: groups,
            flowCategoryIds: spendExcludedIds,
            chartDates: chartRange.dates,
            historyFloor: chartRange.start,
          ).build()
        : const <CategoryTrendSeries>[];
    endPhase('category spend');
    final cashFlows = hasSpendHistory
        ? CashFlowTrendBuilder(
            cashFlowMaps: cashFlowMaps,
            chartDates: chartRange.dates,
            historyFloor: chartRange.start,
          ).build()
        : const <CategoryTrendSeries>[];
    endPhase('cash flows');
    final netWorth = NetWorthTrend.series(
      accounts: accounts,
      transactions: inRangeTransactions,
      chartDates: chartRange.dates,
      ownedAssets: ownedAssets,
      balanceSnapshots: balanceSnapshots,
      importedNetWorthDays: importedNetWorthDays,
    );
    endPhase('net worth');
    return TrendsChartBundle(
      categorySpend: categorySpend,
      cashFlows: cashFlows,
      netWorth: netWorth,
      phaseMillis: phaseMillis,
    );
  }

  static _ChartDateRange? _resolveChartRange({
    required CategorySpendDailyMaps spendMaps,
    required CashFlowDailyMaps cashFlowMaps,
    required List<BankTransaction> inRangeTransactions,
    required List<Account> accounts,
    required List<OwnedAssetWithValuations> ownedAssets,
    required DateTime historyStart,
    required DateTime chartEnd,
  }) {
    final DateTime? earliestSpend = _earliestDay([
      ...spendMaps.totalByDay.keys,
      ...cashFlowMaps.incomeByDay.keys,
      ...cashFlowMaps.spendingByDay.keys,
      ...cashFlowMaps.transferByDay.keys,
    ])?.localMidnight;
    late final DateTime chartStart;
    final hasSpendHistory = earliestSpend != null;
    if (hasSpendHistory) {
      chartStart = earliestSpend.isBefore(historyStart)
          ? historyStart
          : earliestSpend;
    } else if (accounts.isNotEmpty || ownedAssets.isNotEmpty) {
      final DateTime? earliestTxn = _earliestDay([
        for (final transaction in inRangeTransactions) transaction.postedDay,
      ])?.localMidnight;
      chartStart = earliestTxn != null && earliestTxn.isAfter(historyStart)
          ? earliestTxn
          : historyStart;
    } else {
      return null;
    }

    final dates = _calendarDates(chartStart, chartEnd);
    if (dates.length < 2) return null;
    return _ChartDateRange(
      start: chartStart,
      dates: dates,
      hasSpendHistory: hasSpendHistory,
    );
  }

  static CalendarDay? _earliestDay(Iterable<CalendarDay> days) {
    CalendarDay? earliest;
    for (final day in days) {
      if (earliest == null || day.isBefore(earliest)) {
        earliest = day;
      }
    }
    return earliest;
  }

  /// Every local midnight from [firstDate] through [endDate].
  static List<DateTime> _calendarDates(DateTime firstDate, DateTime endDate) {
    final CalendarDay firstDay = firstDate.calendarDay;
    final int dayCount = endDate.calendarDay.daysSince(firstDay) + 1;
    if (dayCount <= 0) return [];
    return List.generate(
      dayCount,
      (dayOffset) => firstDay.plusDays(dayOffset).localMidnight,
    );
  }
}

class const _ChartDateRange({
  required final DateTime start,
  required final List<DateTime> dates,
  required final bool hasSpendHistory,
});
