import 'dart:ui';

import 'package:spend_trends/features/trends/category_trend_plot.dart';
import 'package:spend_trends/features/trends/category_trend_point.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';

/// One series sampled at plot pixels so paint is O(width), not O(days × width).
class PaceLineSamples._({
  required final CategoryTrendSeries series,
  required final List<Offset> offsets,
  required final List<double> percentileRanks,
}) {
  static const columnWidth = 1.0;

  factory alongPlot({
    required CategoryTrendSeries series,
    required CategoryTrendPlot plot,
  }) {
    final points = series.points;
    final layout = plot.chart;
    final scale = plot.scale;
    final offsets = <Offset>[];
    final percentileRanks = <double>[];
    final sortedValues = series.percentileAreaFill
        ? ([for (final point in points) point.smoothedCents]..sort())
        : const <double>[];

    var pointIndex = 0;
    for (
      var columnX = layout.left;
      columnX < layout.right;
      columnX += columnWidth
    ) {
      final sampleDate = layout.dateForX(columnX + columnWidth / 2);
      while (pointIndex < points.length - 1 &&
          points[pointIndex + 1].date.isBefore(sampleDate)) {
        pointIndex++;
      }
      final sampleCents = _interpolatedCents(
        points: points,
        leftIndex: pointIndex,
        sampleDate: sampleDate,
      );
      offsets.add(
        Offset(columnX + columnWidth / 2, scale.yForCents(sampleCents, layout)),
      );
      if (series.percentileAreaFill) {
        percentileRanks.add(percentileRank(sortedValues, sampleCents));
      }
    }

    return PaceLineSamples._(
      series: series,
      offsets: offsets,
      percentileRanks: percentileRanks,
    );
  }

  static double _interpolatedCents({
    required List<CategoryTrendPoint> points,
    required int leftIndex,
    required DateTime sampleDate,
  }) {
    final leftPoint = points[leftIndex];
    if (leftIndex >= points.length - 1) return leftPoint.smoothedCents;
    final rightPoint = points[leftIndex + 1];
    if (sampleDate.isBefore(leftPoint.date)) return leftPoint.smoothedCents;
    if (sampleDate.isAfter(rightPoint.date)) return rightPoint.smoothedCents;
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

  /// Empirical percentile rank in [0, 1] for [value] among [sortedValues].
  static double percentileRank(List<double> sortedValues, double value) {
    if (sortedValues.isEmpty) return 0;
    if (sortedValues.length == 1) return 0.5;

    final countBelow = _firstIndexWhereNotLess(sortedValues, value);
    final countEqual =
        _firstIndexWhereGreater(sortedValues, value) - countBelow;
    return ((countBelow + 0.5 * countEqual) / sortedValues.length).clamp(
      0.0,
      1.0,
    );
  }

  static int _firstIndexWhereNotLess(List<double> sortedValues, double value) {
    var low = 0;
    var high = sortedValues.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (sortedValues[mid] < value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  static int _firstIndexWhereGreater(List<double> sortedValues, double value) {
    var low = 0;
    var high = sortedValues.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (sortedValues[mid] <= value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void paintPercentileRankAsFillOpacity(Canvas canvas, CategoryTrendPlot plot) {
    if (offsets.length < 2) return;

    final baselineY = plot.scale.yForCents(0, plot.chart);
    final positions = <Offset>[];
    final colors = <Color>[];
    for (var sampleIndex = 0; sampleIndex < offsets.length; sampleIndex++) {
      final top = offsets[sampleIndex];
      final columnHeight = baselineY - top.dy;
      final peakAlpha = columnHeight < 1
          ? 0.0
          : 0.14 + 0.42 * percentileRanks[sampleIndex];
      positions
        ..add(top)
        ..add(Offset(top.dx, baselineY));
      colors
        ..add(series.lineColor.withValues(alpha: peakAlpha))
        ..add(series.lineColor.withValues(alpha: 0));
    }

    canvas.drawVertices(
      Vertices(VertexMode.triangleStrip, positions, colors: colors),
      BlendMode.srcOver,
      Paint(),
    );
  }

  void paintStroke(Canvas canvas) {
    if (offsets.length < 2) return;

    final linePaint = Paint()
      ..color = series.lineColor
      ..strokeWidth = series.guide
          ? 1.25
          : series.dotted
          ? 2.5
          : 2
      ..style = PaintingStyle.stroke
      ..strokeCap = series.guide ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (series.guide) {
      canvas.drawPath(
        dashedPolylinePath(offsets, dashLength: 8, gapLength: 10),
        linePaint,
      );
      return;
    }
    if (series.dotted) {
      canvas.drawPath(dashedPolylinePath(offsets), linePaint);
      return;
    }
    canvas.drawPath(solidPolylinePath(offsets), linePaint);
  }

  static Path solidPolylinePath(List<Offset> offsets) {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var offsetIndex = 1; offsetIndex < offsets.length; offsetIndex++) {
      path.lineTo(offsets[offsetIndex].dx, offsets[offsetIndex].dy);
    }
    return path;
  }

  static Path dashedPolylinePath(
    List<Offset> offsets, {
    double dashLength = 5,
    double gapLength = 4,
  }) {
    final path = Path();
    var drawingDash = true;
    var phaseRemaining = dashLength;
    for (
      var segmentIndex = 0;
      segmentIndex < offsets.length - 1;
      segmentIndex++
    ) {
      final start = offsets[segmentIndex];
      final end = offsets[segmentIndex + 1];
      final segment = end - start;
      final segmentLength = segment.distance;
      if (segmentLength <= 0) continue;
      final direction = segment / segmentLength;
      var drawn = 0.0;
      while (drawn < segmentLength) {
        final step = phaseRemaining < segmentLength - drawn
            ? phaseRemaining
            : segmentLength - drawn;
        if (drawingDash && step > 0.25) {
          final dashStart = start + direction * drawn;
          final dashEnd = start + direction * (drawn + step);
          path
            ..moveTo(dashStart.dx, dashStart.dy)
            ..lineTo(dashEnd.dx, dashEnd.dy);
        }
        drawn += step;
        phaseRemaining -= step;
        if (phaseRemaining <= 0) {
          drawingDash = !drawingDash;
          phaseRemaining = drawingDash ? dashLength : gapLength;
        }
      }
    }
    return path;
  }

  static Path dashedHorizontalPath({
    required Offset start,
    required double endX,
    double dashLength = 4,
    double gapLength = 3,
  }) {
    final path = Path();
    var x = start.dx;
    var drawingDash = true;
    while (x < endX) {
      final next = x + (drawingDash ? dashLength : gapLength);
      final clampedNext = next < endX ? next : endX;
      if (drawingDash) {
        path
          ..moveTo(x, start.dy)
          ..lineTo(clampedNext, start.dy);
      }
      x = clampedNext;
      drawingDash = !drawingDash;
    }
    return path;
  }
}
