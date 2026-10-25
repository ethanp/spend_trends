import 'package:flutter/material.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers.dart';

class const TrendsChartBundle({
  required final List<CategoryTrendSeries> categorySpend,
  required final List<CategoryTrendSeries> cashFlows,
  required final ConsciousSpendingNumbers consciousSpendingNumbers,
  final List<CategoryTrendSeries> netWorth = const [],
}) {
  bool get isEmpty =>
      categorySpend.isEmpty && cashFlows.isEmpty && netWorth.isEmpty;

  /// First to last plotted day across every Trends chart.
  DateTimeRange? get chartedDateRange {
    DateTime? earliest;
    DateTime? latest;
    for (final series in [...cashFlows, ...netWorth, ...categorySpend]) {
      if (!series.canPlot) continue;
      final firstDate = series.points.first.date;
      final lastDate = series.points.last.date;
      if (earliest == null || firstDate.isBefore(earliest)) {
        earliest = firstDate;
      }
      if (latest == null || lastDate.isAfter(latest)) latest = lastDate;
    }
    if (earliest == null || latest == null || !earliest.isBefore(latest)) {
      return null;
    }
    return DateTimeRange(start: earliest, end: latest);
  }
}
