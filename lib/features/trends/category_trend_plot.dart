import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/trend_overlay_lane.dart';
import 'package:spend_trends/features/trends/trend_value_scale.dart';

/// Laid-out Trends chart: date axis, value scale, and drawable series.
class CategoryTrendPlot._({
  required final EChartPlot chart,
  required final TrendValueScale scale,
  required final List<CategoryTrendSeries> drawableSeries,
  required final List<TrendOverlayLane> overlayLanes,
}) {
  static const leftPadding = 48.0;
  static const rightPadding = 12.0;
  static const bottomPadding = 24.0;
  static const _plotTopInset = 12.0;

  factory from({
    required Size size,
    required List<CategoryTrendSeries> seriesList,
    EChartVisibleRange? visibleRange,
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
    EChartPlot chartBelow(double topPadding) => EChartPlot(
      size: size,
      leftPadding: leftPadding,
      rightPadding: rightPadding,
      topPadding: topPadding,
      bottomPadding: bottomPadding,
      start: plottedDates.start,
      end: plottedDates.end,
      valueScale: EChartValueScale.nice(
        highestSmoothedCents,
        fallbackMax: 10000,
      ),
    );
    final xAxis = chartBelow(0);
    final chartMin = plottedDates.start.startOfDay;
    final chartMax = plottedDates.end.startOfDay;
    final visibleLifeEvents =
        [
          for (final lifeEvent in lifeEvents)
            if (lifeEvent.intersectsChart(
              chartMinDate: chartMin,
              chartMaxDate: chartMax,
            ))
              lifeEvent,
        ]..sort(
          (firstEvent, secondEvent) =>
              firstEvent.startedOn.compareTo(secondEvent.startedOn),
        );
    final overlayLanes = <TrendOverlayLane>[];
    for (final lifeEventLane in LifeEventLane.values) {
      final laneLifeEvents = visibleLifeEvents.whereL(
        (lifeEvent) => lifeEvent.kind.lane == lifeEventLane,
      );
      if (laneLifeEvents.isEmpty) continue;
      overlayLanes.add(
        TrendOverlayLane.stackedBelow(
          top: overlayLanes.isEmpty ? 0 : overlayLanes.last.bottom,
          xAxis: xAxis,
          lifeEventLane: lifeEventLane,
          visibleLifeEvents: laneLifeEvents,
        ),
      );
    }
    return CategoryTrendPlot._(
      chart: chartBelow(
        overlayLanes.isEmpty ? _plotTopInset : overlayLanes.last.bottom,
      ),
      scale: TrendValueScale.niceForMax(highestSmoothedCents),
      drawableSeries: drawableSeries,
      overlayLanes: overlayLanes,
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
