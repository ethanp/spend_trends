import 'package:flutter/material.dart';
import 'package:spend_trends/features/trends/category_trend_point.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

class const CategoryTrendSeries({
  /// Category id, or `'__all__'` for total spend.
  required final String id,
  required final String name,
  required final Color lineColor,
  required final List<CategoryTrendPoint> points,

  /// Total-spend overlay uses a dotted stroke so it reads apart from categories.
  final bool dotted = false,

  /// Thin long-dash reference line (e.g. affordability threshold).
  final bool guide = false,

  /// Fill under the line; opacity encodes each point's percentile in the series.
  final bool percentileAreaFill = false,

  /// Optional legend section header (e.g. bank institution for net worth).
  final String? legendGroup,
  final String? legendCaption,

  /// Group rollup series this category belongs to, when this is a member line.
  final String? memberOfGroupSeriesId,
}) {
  double get latestSmoothedCents =>
      points.isEmpty ? 0 : points.last.smoothedCents;

  double get latestRollingCents =>
      points.isEmpty ? 0 : points.last.rollingCents;

  static const minMeaningfulCents = 100.0;

  /// Enough magnitude to show in Trends (smoothed or rolling).
  bool get hasMeaningfulTrend {
    for (final point in points) {
      if (point.smoothedCents.abs() >= minMeaningfulCents ||
          point.rollingCents.abs() >= minMeaningfulCents) {
        return true;
      }
    }
    return false;
  }

  bool get isMemberOfGroup => memberOfGroupSeriesId != null;

  bool get isAllSpend => id == TrendChartCatalog.allSpendSeriesId;

  bool get isMetaLegend =>
      isAllSpend ||
      id == TrendChartCatalog.netWorthSeriesId ||
      id == TrendChartCatalog.housingAffordabilitySeriesId ||
      id == TrendChartCatalog.uncategorizedSeriesId;

  bool get canPlot => points.length >= 2;

  /// Linear interpolation of [smoothedCents] at [sampleDate].
  double smoothedCentsAt(DateTime sampleDate) {
    if (points.isEmpty) return 0;
    final firstPoint = points.first;
    final lastPoint = points.last;
    if (sampleDate.isBefore(firstPoint.date)) return firstPoint.smoothedCents;
    if (sampleDate.isAfter(lastPoint.date)) return lastPoint.smoothedCents;

    final rightIndex = _firstIndexOnOrAfter(sampleDate);
    final rightPoint = points[rightIndex];
    if (rightIndex == 0) return rightPoint.smoothedCents;
    final leftPoint = points[rightIndex - 1];
    final spanSeconds = rightPoint.date
        .difference(leftPoint.date)
        .inSeconds
        .toDouble();
    if (spanSeconds <= 0) return leftPoint.smoothedCents;
    final t = sampleDate.difference(leftPoint.date).inSeconds / spanSeconds;
    return leftPoint.smoothedCents +
        (rightPoint.smoothedCents - leftPoint.smoothedCents) *
            t.clamp(0.0, 1.0);
  }

  CategoryTrendPoint? nearestPoint(DateTime hoverDate) {
    if (points.isEmpty) return null;
    if (points.length == 1) return points.first;

    final rightIndex = _firstIndexOnOrAfter(hoverDate);
    final rightPoint = points[rightIndex];
    if (rightIndex == 0) return rightPoint;
    final leftPoint = points[rightIndex - 1];
    final rightDelta = rightPoint.date.difference(hoverDate).inSeconds.abs();
    final leftDelta = leftPoint.date.difference(hoverDate).inSeconds.abs();
    return leftDelta <= rightDelta ? leftPoint : rightPoint;
  }

  /// First index whose date is >= [sampleDate], or the last index if all are before.
  int _firstIndexOnOrAfter(DateTime sampleDate) {
    var low = 0;
    var high = points.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (points[mid].date.isBefore(sampleDate)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
