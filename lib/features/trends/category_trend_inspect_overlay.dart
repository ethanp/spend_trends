import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/features/trends/category_trend_plot.dart';

/// Inspected calendar day on a Trends chart (hairline + legend as-of).
class const CategoryTrendInspect({required final DateTime date}) {
  @override
  bool operator ==(Object other) =>
      other is CategoryTrendInspect && other.date == date;

  @override
  int get hashCode => date.hashCode;
}

/// Hairline and pace rings for the inspected date. Cheap to repaint on hover.
class CategoryTrendInspectPainter({
  required final CategoryTrendPlot plot,
  required final CategoryTrendInspect? inspect,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final inspectTarget = inspect;
    if (inspectTarget == null) return;

    final hoverDate = inspectTarget.date;
    final hoveredX = plot.chart.xForDate(hoverDate);
    final markerPaint = Paint()
      ..color = EColors.textMuted.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(hoveredX, plot.chart.top),
      Offset(hoveredX, plot.chart.bottom),
      markerPaint,
    );

    for (final series in plot.drawableSeries) {
      final point = series.nearestPoint(hoverDate);
      if (point == null) continue;
      final ringPaint = Paint()
        ..color = series.lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(
        Offset(hoveredX, plot.scale.yForCents(point.smoothedCents, plot.chart)),
        4,
        ringPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CategoryTrendInspectPainter oldDelegate) =>
      inspect != oldDelegate.inspect ||
      plot.drawableSeries != oldDelegate.plot.drawableSeries;
}
