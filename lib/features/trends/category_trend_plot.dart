import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/trend_value_scale.dart';

/// Laid-out Trends chart: date axis, value scale, and drawable series.
class CategoryTrendPlot._({
  required final EChartPlot chart,
  required final TrendValueScale scale,
  required final List<CategoryTrendSeries> drawableSeries,
  final int? housingLane,
  final int? jobLane,
  final int? lifeEventLane,
}) {
  static const leftPadding = 48.0;
  static const rightPadding = 12.0;
  static const bottomPadding = 24.0;
  static const overlayLaneHeight = 44.0;
  static const _plotTopInset = 12.0;

  factory from({
    required Size size,
    required List<CategoryTrendSeries> seriesList,
    EChartVisibleRange? visibleRange,
    StayChain? housingChain,
    StayChain? jobChain,
    List<LifeEvent> lifeEvents = const [],
  }) {
    final plottableSeries = [
      for (final series in seriesList)
        if (series.canPlot) series,
    ];
    final plottedDates = _plottedDates(plottableSeries, visibleRange);
    final drawableSeries = [
      for (final series in plottableSeries)
        if (series.hasPointsBetween(plottedDates.start, plottedDates.end))
          series,
    ];
    var nextLane = 0;
    final housingLane = housingChain != null && !housingChain.isEmpty
        ? nextLane++
        : null;
    final jobLane = jobChain != null && !jobChain.isEmpty ? nextLane++ : null;
    final lifeEventLane = lifeEvents.isNotEmpty ? nextLane++ : null;
    var highestSmoothedCents = 0.0;
    for (final series in drawableSeries) {
      highestSmoothedCents = math.max(
        highestSmoothedCents,
        series.highestSmoothedCentsBetween(
          plottedDates.start,
          plottedDates.end,
        ),
      );
    }
    return CategoryTrendPlot._(
      chart: EChartPlot(
        size: size,
        leftPadding: leftPadding,
        rightPadding: rightPadding,
        topPadding: nextLane == 0
            ? _plotTopInset
            : nextLane * overlayLaneHeight,
        bottomPadding: bottomPadding,
        start: plottedDates.start,
        end: plottedDates.end,
        valueScale: EChartValueScale.nice(
          highestSmoothedCents,
          fallbackMax: 10000,
        ),
      ),
      scale: TrendValueScale.niceForMax(highestSmoothedCents),
      drawableSeries: drawableSeries,
      housingLane: housingLane,
      jobLane: jobLane,
      lifeEventLane: lifeEventLane,
    );
  }

  /// This chart's own history, narrowed to [visibleRange] where they overlap.
  static DateTimeRange _plottedDates(
    List<CategoryTrendSeries> plottableSeries,
    EChartVisibleRange? visibleRange,
  ) {
    final firstDate = plottableSeries
        .map((series) => series.points.first.date)
        .reduce((earlier, later) => earlier.isBefore(later) ? earlier : later);
    final lastDate = plottableSeries
        .map((series) => series.points.last.date)
        .reduce((earlier, later) => earlier.isAfter(later) ? earlier : later);
    if (visibleRange == null) {
      return DateTimeRange(start: firstDate, end: lastDate);
    }
    final start = visibleRange.start.isAfter(firstDate)
        ? visibleRange.start
        : firstDate;
    final end = visibleRange.end.isBefore(lastDate)
        ? visibleRange.end
        : lastDate;
    if (!start.isBefore(end)) {
      return DateTimeRange(start: visibleRange.start, end: visibleRange.end);
    }
    return DateTimeRange(start: start, end: end);
  }

  DateTime dateForX(double x) => chart.dateForX(x);
}
