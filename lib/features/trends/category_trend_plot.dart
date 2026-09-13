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
  static const overlayLaneHeight = 34.0;
  static const _plotTopInset = 12.0;

  factory from({
    required Size size,
    required List<CategoryTrendSeries> seriesList,
    StayChain? housingChain,
    StayChain? jobChain,
    List<LifeEvent> lifeEvents = const [],
  }) {
    final drawableSeries = [
      for (final series in seriesList)
        if (series.canPlot) series,
    ];
    var nextLane = 0;
    final housingLane = housingChain != null && !housingChain.isEmpty
        ? nextLane++
        : null;
    final jobLane = jobChain != null && !jobChain.isEmpty ? nextLane++ : null;
    final lifeEventLane = lifeEvents.isNotEmpty ? nextLane++ : null;
    final highestSmoothedCents = _highestSmoothedCents(drawableSeries);
    return CategoryTrendPlot._(
      chart: _dateRangeLayout(
        size,
        drawableSeries,
        overlayLaneCount: nextLane,
        highestSmoothedCents: highestSmoothedCents,
      ),
      scale: TrendValueScale.niceForMax(highestSmoothedCents),
      drawableSeries: drawableSeries,
      housingLane: housingLane,
      jobLane: jobLane,
      lifeEventLane: lifeEventLane,
    );
  }

  static double _highestSmoothedCents(
    List<CategoryTrendSeries> drawableSeries,
  ) {
    var highest = 0.0;
    for (final series in drawableSeries) {
      for (final point in series.points) {
        highest = math.max(highest, point.smoothedCents);
      }
    }
    return highest;
  }

  static EChartPlot _dateRangeLayout(
    Size size,
    List<CategoryTrendSeries> drawableSeries, {
    required int overlayLaneCount,
    required double highestSmoothedCents,
  }) {
    final firstDate = drawableSeries
        .map((series) => series.points.first.date)
        .reduce((earlier, later) => earlier.isBefore(later) ? earlier : later);
    final lastDate = drawableSeries
        .map((series) => series.points.last.date)
        .reduce((earlier, later) => earlier.isAfter(later) ? earlier : later);
    return EChartPlot(
      size: size,
      leftPadding: leftPadding,
      rightPadding: rightPadding,
      topPadding: overlayLaneCount == 0
          ? _plotTopInset
          : overlayLaneCount * overlayLaneHeight,
      bottomPadding: bottomPadding,
      start: firstDate,
      end: lastDate,
      valueScale: EChartValueScale.nice(
        highestSmoothedCents,
        fallbackMax: 10000,
      ),
    );
  }

  DateTime dateForX(double x) => chart.dateForX(x);
}
