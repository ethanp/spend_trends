import 'package:flutter/material.dart';
import 'package:spend_trends/ui/trends/category_trend_series.dart';

class const TrendsChartBundle({
  required final List<CategoryTrendSeries> categorySpend,
  required final List<CategoryTrendSeries> cashFlows,
  final List<CategoryTrendSeries> netWorth = const [],

  /// Milliseconds each build phase took, in build order, for the app log.
  final Map<String, int> phaseMillis = const {},
}) {
  String get phaseSummary =>
      [for (final phase in phaseMillis.entries) '${phase.key} ${phase.value}ms']
          .join(', ');

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
