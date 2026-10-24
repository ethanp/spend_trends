import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/cash_flow_breakdown.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/annual_pace_smoother.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

/// Daily take-home pay / spending / transfer / conscious-spending-area totals
/// for cash-flow Trends, summed from [CashFlowBreakdown] contributions.
class const CashFlowDailyMaps({
  required final Map<DateTime, double> incomeByDay,
  required final Map<DateTime, double> spendingByDay,
  required final Map<DateTime, double> transferByDay,
  final Map<ConsciousSpendingArea, Map<DateTime, double>>
      consciousSpendingByArea =
      const {},
}) {
  static CashFlowDailyMaps fromTransactions(
    List<BankTransaction> transactions, {
    List<SpendCategory> categories = const [],
    List<Account> accounts = const [],
  }) {
    final cashFlowBreakdown = CashFlowBreakdown(
      categories: categories,
      accounts: accounts,
    );
    final incomeByDay = <DateTime, double>{};
    final spendingByDay = <DateTime, double>{};
    final transferByDay = <DateTime, double>{};
    final consciousSpendingByArea = {
      for (final area in ConsciousSpendingArea.values)
        area: <DateTime, double>{},
    };

    for (final transaction in transactions) {
      final contribution = cashFlowBreakdown.contributionOf(transaction);
      final day = transaction.postedAt.startOfDay;
      _addCents(incomeByDay, day, contribution.takeHomeCents);
      _addCents(spendingByDay, day, contribution.spendingCents);
      _addCents(transferByDay, day, contribution.transferCents);
      final area = contribution.area;
      if (area != null) {
        _addCents(consciousSpendingByArea[area]!, day, contribution.areaCents);
      }
    }

    return CashFlowDailyMaps(
      incomeByDay: incomeByDay,
      spendingByDay: spendingByDay,
      transferByDay: transferByDay,
      consciousSpendingByArea: consciousSpendingByArea,
    );
  }

  static void _addCents(
    Map<DateTime, double> centsByDay,
    DateTime day,
    int cents,
  ) {
    if (cents == 0) return;
    centsByDay.update(
      day,
      (priorCents) => priorCents + cents,
      ifAbsent: () => cents.toDouble(),
    );
  }
}

/// Builds Income / Spending / Savings / Transfer / FIRE guide series.
class const CashFlowTrendBuilder({
  required final CashFlowDailyMaps cashFlowMaps,
  required final List<DateTime> chartDates,
  required final DateTime historyFloor,
}) {
  List<CategoryTrendSeries> build() {
    final savingsByDay = _dailySavingsMap(
      incomeByDay: cashFlowMaps.incomeByDay,
      spendingByDay: cashFlowMaps.spendingByDay,
    );
    final fireSavingsGuideByDay = {
      for (final entry in cashFlowMaps.incomeByDay.entries)
        entry.key: entry.value * TrendChartCatalog.fireSavingsIncomeShare,
    };

    final series = <CategoryTrendSeries>[
      _paceSeries(
        id: TrendChartCatalog.incomeSeriesId,
        name: 'Income',
        lineColor: TrendChartCatalog.incomeLineColor,
        percentileAreaFill: true,
        dailyCents: cashFlowMaps.incomeByDay,
      ),
      _paceSeries(
        id: TrendChartCatalog.spendingSeriesId,
        name: 'Spending',
        lineColor: TrendChartCatalog.spendingLineColor,
        percentileAreaFill: true,
        dailyCents: cashFlowMaps.spendingByDay,
      ),
      _paceSeries(
        id: TrendChartCatalog.savingsSeriesId,
        name: 'Savings',
        lineColor: TrendChartCatalog.savingsLineColor,
        legendCaption: 'Income − Spending',
        dailyCents: savingsByDay,
      ),
      for (final area in ConsciousSpendingArea.values)
        _paceSeries(
          id: TrendChartCatalog.consciousSpendingAreaSeriesId(area),
          name: area.displayName,
          lineColor: area.color,
          dailyCents: cashFlowMaps.consciousSpendingByArea[area] ?? const {},
        ),
      _paceSeries(
        id: TrendChartCatalog.fireSavingsGuideSeriesId,
        name: '25% of income',
        lineColor: TrendChartCatalog.fireSavingsGuideLineColor,
        legendCaption: 'FIRE guide',
        guide: true,
        dailyCents: fireSavingsGuideByDay,
      ),
      _paceSeries(
        id: TrendChartCatalog.transferSeriesId,
        name: 'Transfer',
        lineColor: TrendChartCatalog.transferLineColor,
        dailyCents: cashFlowMaps.transferByDay,
      ),
    ];
    return series.where((series) => series.hasMeaningfulTrend).toList();
  }

  CategoryTrendSeries _paceSeries({
    required String id,
    required String name,
    required Color lineColor,
    required Map<DateTime, double> dailyCents,
    bool guide = false,
    bool percentileAreaFill = false,
    String? legendCaption,
  }) {
    return AnnualPaceSmoother.standard.seriesFromDailyMap(
      id: id,
      name: name,
      lineColor: lineColor,
      guide: guide,
      percentileAreaFill: percentileAreaFill,
      legendCaption: legendCaption,
      dailyCents: dailyCents,
      chartDates: chartDates,
      historyFloor: historyFloor,
    );
  }

  static Map<DateTime, double> _dailySavingsMap({
    required Map<DateTime, double> incomeByDay,
    required Map<DateTime, double> spendingByDay,
  }) {
    final days = {...incomeByDay.keys, ...spendingByDay.keys};
    return {
      for (final day in days)
        day: (incomeByDay[day] ?? 0) - (spendingByDay[day] ?? 0),
    };
  }
}
