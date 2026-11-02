import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/painting.dart';

/// Clipped date-range band for Trends overlays (life events, housing, job).
class const DateRangeBandGeometry({
  required final double leftX,
  required final double rightX,
  required final bool drawLeftEdge,
  required final bool drawRightEdge,
});

/// Lane fill treatments that alternate between consecutive chain eras.
enum DateRangeBandFillStyle() {
  /// Uniform tint across the band.
  solid,

  /// Sparse diagonal hatch in the band accent.
  hatch,
}

/// Computes chart-clipped band geometry, or null when the range is empty.
DateRangeBandGeometry? dateRangeBandGeometry({
  required EChartPlot plot,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required bool showLeftEdge,
  required bool showRightEdge,
}) {
  final chartMin = plot.start.startOfDay;
  final chartMax = plot.end.startOfDay;
  var bandStart = rangeStart.startOfDay;
  var bandEnd = rangeEnd.startOfDay;
  if (bandStart.isBefore(chartMin)) bandStart = chartMin;
  if (bandEnd.isAfter(chartMax)) bandEnd = chartMax;
  if (bandEnd.isBefore(bandStart)) return null;

  final leftX = plot.xForDate(bandStart);
  final rightX = plot.xForDate(bandEnd);
  return DateRangeBandGeometry(
    leftX: leftX,
    rightX: math.max(leftX + 1, rightX),
    drawLeftEdge: showLeftEdge && !rangeStart.startOfDay.isBefore(chartMin),
    drawRightEdge: showRightEdge && !rangeEnd.startOfDay.isAfter(chartMax),
  );
}

/// Label X at the visible left of a range (clamped into the chart).
double dateRangeLabelAnchorX({
  required EChartPlot plot,
  required DateTime rangeStart,
}) {
  final chartMin = plot.start.startOfDay;
  final chartMax = plot.end.startOfDay;
  final visibleStart = rangeStart.startOfDay.isBefore(chartMin)
      ? chartMin
      : rangeStart.startOfDay;
  final clampedStart = visibleStart.isAfter(chartMax) ? chartMax : visibleStart;
  return plot.xForDate(clampedStart);
}

void paintDateRangeBand(
  Canvas canvas, {
  required EChartPlot plot,
  required DateRangeBandGeometry geometry,
  required Paint edgePaint,
  Paint? fillPaint,
  Color? fillColor,
  DateRangeBandFillStyle fillStyle = DateRangeBandFillStyle.solid,
  double fillAlpha = 0.12,
  double? fillTop,
  double? fillBottom,
  double? edgeTop,
  double? edgeBottom,
}) {
  final resolvedFillTop = fillTop ?? plot.top;
  final resolvedFillBottom = fillBottom ?? plot.bottom;
  final resolvedEdgeTop = edgeTop ?? plot.top;
  final resolvedEdgeBottom = edgeBottom ?? plot.bottom;

  final fillRect = Rect.fromLTRB(
    geometry.leftX,
    resolvedFillTop,
    geometry.rightX,
    resolvedFillBottom,
  );
  if (fillPaint != null) {
    canvas.drawRect(fillRect, fillPaint);
  } else if (fillColor != null) {
    _fillBandSolidOrHatch(
      canvas,
      bandRect: fillRect,
      color: fillColor,
      style: fillStyle,
      alpha: fillAlpha,
    );
  }
  if (geometry.drawLeftEdge) {
    canvas.drawLine(
      Offset(geometry.leftX, resolvedEdgeTop),
      Offset(geometry.leftX, resolvedEdgeBottom),
      edgePaint,
    );
  }
  if (geometry.drawRightEdge) {
    canvas.drawLine(
      Offset(geometry.rightX, resolvedEdgeTop),
      Offset(geometry.rightX, resolvedEdgeBottom),
      edgePaint,
    );
  }
}

void _fillBandSolidOrHatch(
  Canvas canvas, {
  required Rect bandRect,
  required Color color,
  required DateRangeBandFillStyle style,
  required double alpha,
}) {
  switch (style) {
    case DateRangeBandFillStyle.solid:
      canvas.drawRect(
        bandRect,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.fill,
      );
    case DateRangeBandFillStyle.hatch:
      _strokeSparseDiagonalHatch(
        canvas,
        bandRect: bandRect,
        color: color,
        alpha: math.min(1.0, alpha + 0.10),
      );
  }
}

void _strokeSparseDiagonalHatch(
  Canvas canvas, {
  required Rect bandRect,
  required Color color,
  required double alpha,
}) {
  if (bandRect.width <= 0 || bandRect.height <= 0) return;

  canvas.save();
  canvas.clipRect(bandRect);

  final hatchPaint = Paint()
    ..color = color.withValues(alpha: alpha)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;

  const spacing = 7.0;
  // Diagonals from lower-left toward upper-right; cover the clipped rect.
  final minX = bandRect.left - bandRect.height;
  final maxX = bandRect.right + bandRect.height;
  for (var x = minX; x < maxX; x += spacing) {
    canvas.drawLine(
      Offset(x, bandRect.bottom),
      Offset(x + bandRect.height, bandRect.top),
      hatchPaint,
    );
  }

  canvas.restore();
}
