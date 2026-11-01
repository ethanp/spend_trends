import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/month_summary.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/annual_pace_smoother.dart';
import 'package:spend_trends/features/trends/hann_annual_pace_kernel.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:ethan_utils/ethan_utils.dart';

/// Per-category spend for one month beside its trailing-year pace, from the
/// transactions the app already holds in memory.
class const BudgetMonth._() {
  static List<CategoryMonthRow> categoryRows({
    required String yearMonth,
    required DateTime now,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
  }) {
    final monthParts = yearMonth.split('-');
    final monthStart = CalendarDay.of(
      int.parse(monthParts[0]),
      int.parse(monthParts[1]),
      1,
    );
    final monthEnd = monthStart.startOfNextMonth;
    final int nowMillis = now.millisecondsSinceEpoch;
    final int trailingYearStartMillis =
        nowMillis -
        HannAnnualPaceKernel.defaultYearDays * Duration.millisecondsPerDay;
    final monthOutflows = _outflowByCategory([
      for (final transaction in transactions)
        if (!transaction.postedDay.isBefore(monthStart) &&
            transaction.postedDay.isBefore(monthEnd))
          transaction,
    ]);
    final trailingYearOutflows = _outflowByCategory([
      for (final transaction in transactions)
        if (transaction.postedAtMillis >= trailingYearStartMillis &&
            transaction.postedAtMillis < nowMillis)
          transaction,
    ]);
    final observedDays = _observedTrailingDays();

    return [
      for (final category in categories)
        if (!category.isFlow)
          CategoryMonthRow(
            categoryId: category.id,
            categoryName: category.name,
            annualizedSpendCents: AnnualPaceSmoother.annualizeTrailingTotal(
              windowTotalCents: (trailingYearOutflows[category.id] ?? 0)
                  .toDouble(),
              observedDays: observedDays,
            ).round(),
            spentCents: monthOutflows[category.id] ?? 0,
          ),
    ];
  }

  /// Calendar days on or after [chartHistoryStart] inside the trailing window.
  static int _observedTrailingDays() {
    final today = DateTime.now().startOfDay;
    final historyFloor = TrendChartCatalog.chartHistoryStart.startOfDay;
    final windowFloor = today.shiftedByDays(
      -(HannAnnualPaceKernel.defaultYearDays - 1),
    );
    final effectiveFloor = windowFloor.isBefore(historyFloor)
        ? historyFloor
        : windowFloor;
    final observedDays = today.difference(effectiveFloor).inDays + 1;
    if (observedDays < 1) return 1;
    if (observedDays > HannAnnualPaceKernel.defaultYearDays) {
      return HannAnnualPaceKernel.defaultYearDays;
    }
    return observedDays;
  }

  static Map<String, int> _outflowByCategory(
    List<BankTransaction> transactions,
  ) {
    final spentByCategory = <String, int>{};
    for (final transaction in transactions) {
      if (!transaction.isOutflow) continue;
      final categoryId = transaction.categoryId;
      if (categoryId == null) continue;
      spentByCategory.update(
        categoryId,
        (priorSpendCents) => priorSpendCents + -transaction.amountCents,
        ifAbsent: () => -transaction.amountCents,
      );
    }
    return spentByCategory;
  }
}
