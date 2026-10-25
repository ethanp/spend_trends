import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

import 'trends_providers.dart';

/// All-history miniature of income, spending and savings; the dragged window
/// narrows every Trends chart.
class const TrendRangeScrubber({
  required final DateTimeRange chartedDateRange,
  required final List<EChartAllTimeRangeLine> cashFlowLines,
}) extends ConsumerWidget {
  static const _height = 44.0;

  /// One minimap line per plotted cash flow, skipping guides and transfers.
  static List<EChartAllTimeRangeLine> cashFlowLinesFrom(
    List<CategoryTrendSeries> cashFlows,
  ) => [
    for (final series in cashFlows)
      if (series.canPlot &&
          !series.guide &&
          series.id != TrendChartCatalog.transferSeriesId)
        EChartAllTimeRangeLine(
          color: series.lineColor,
          samples: [
            for (final point in series.points)
              EChartAllTimeRangeSample(
                date: point.date,
                value: point.smoothedCents,
              ),
          ],
        ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EChartVisibleRange? visibleRange = ref.watch(
      trendVisibleRangeProvider,
    );
    return EChartAllTimeRangeScrubber(
      rangeStart: chartedDateRange.start,
      rangeEnd: chartedDateRange.end,
      lines: cashFlowLines,
      height: _height,
      visible:
          visibleRange?.clampedTo(
            earliest: chartedDateRange.start,
            latest: chartedDateRange.end,
          ) ??
          EChartVisibleRange(
            start: chartedDateRange.start,
            end: chartedDateRange.end,
          ),
      onVisibleRangeChanged: ref
          .read(trendVisibleRangeProvider.notifier)
          .setVisibleRange,
    );
  }
}
