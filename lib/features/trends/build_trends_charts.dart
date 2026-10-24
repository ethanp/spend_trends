import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/cash_flow_trend_builder.dart';
import 'package:spend_trends/features/trends/category_spend_trend_builder.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers.dart';
import 'package:spend_trends/features/trends/net_worth_trend.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/features/trends/trends_chart_bundle.dart';
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
    DateTime? endDate,
  }) {
    final chartEnd = (endDate ?? DateTime.now()).startOfDay;
    final historyStart = TrendChartCatalog.chartHistoryStart.startOfDay;
    final inRangeTransactions = [
      for (final transaction in transactions)
        if (!transaction.postedAt.isBefore(historyStart)) transaction,
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

    final consciousSpendingNumbers = ConsciousSpendingNumbers.endingOn(
      transactions: transactions,
      categories: categories,
      accounts: accounts,
      today: chartEnd,
    );

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
      return TrendsChartBundle(
        categorySpend: const [],
        cashFlows: const [],
        consciousSpendingNumbers: consciousSpendingNumbers,
      );
    }

    final hasSpendHistory = chartRange.hasSpendHistory;
    return TrendsChartBundle(
      consciousSpendingNumbers: consciousSpendingNumbers,
      categorySpend: hasSpendHistory
          ? CategorySpendTrendBuilder(
              spendMaps: spendMaps,
              incomeByDay: cashFlowMaps.incomeByDay,
              categories: categories,
              groups: groups,
              flowCategoryIds: spendExcludedIds,
              chartDates: chartRange.dates,
              historyFloor: chartRange.start,
            ).build()
          : const [],
      cashFlows: hasSpendHistory
          ? CashFlowTrendBuilder(
              cashFlowMaps: cashFlowMaps,
              chartDates: chartRange.dates,
              historyFloor: chartRange.start,
            ).build()
          : const [],
      netWorth: NetWorthTrend.series(
        accounts: accounts,
        transactions: inRangeTransactions,
        chartDates: chartRange.dates,
        ownedAssets: ownedAssets,
        balanceSnapshots: balanceSnapshots,
      ),
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
    final earliestSpend = _earliestDate([
      ...spendMaps.totalByDay.keys,
      ...cashFlowMaps.incomeByDay.keys,
      ...cashFlowMaps.spendingByDay.keys,
      ...cashFlowMaps.transferByDay.keys,
    ]);
    final earliestTxn = _earliestDate([
      for (final transaction in inRangeTransactions)
        transaction.postedAt.startOfDay,
    ]);

    late final DateTime chartStart;
    final hasSpendHistory = earliestSpend != null;
    if (hasSpendHistory) {
      chartStart = earliestSpend.isBefore(historyStart)
          ? historyStart
          : earliestSpend;
    } else if (accounts.isNotEmpty || ownedAssets.isNotEmpty) {
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

  static DateTime? _earliestDate(Iterable<DateTime> dates) {
    DateTime? earliest;
    for (final day in dates) {
      if (earliest == null || day.isBefore(earliest)) {
        earliest = day;
      }
    }
    return earliest;
  }

  static List<DateTime> _calendarDates(DateTime firstDate, DateTime endDate) {
    if (firstDate.isAfter(endDate)) return [];
    final dayCount = endDate.difference(firstDate).inDays + 1;
    return List.generate(
      dayCount,
      (dayOffset) => firstDate.shiftedByDays(dayOffset),
    );
  }
}

class const _ChartDateRange({
  required final DateTime start,
  required final List<DateTime> dates,
  required final bool hasSpendHistory,
});
