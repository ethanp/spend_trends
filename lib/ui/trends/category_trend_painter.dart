import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/trends/trend_spend_rate.dart';
import 'package:spend_trends/ui/trends/category_trend_plot.dart';
import 'package:spend_trends/ui/trends/category_trend_series.dart';
import 'package:spend_trends/ui/trends/pace_line_samples.dart';

class CategoryTrendPainter({
  required final List<CategoryTrendSeries> seriesList,
  final EChartVisibleRange? visibleRange,
  final List<LifeEvent> lifeEvents = const [],
  required final TrendSpendRate spendRate,
  required final TrendValueKind valueKind,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (!seriesList.any((series) => series.canPlot)) return;

    _CategoryTrendChartFrame(
      canvas: canvas,
      plot: CategoryTrendPlot.from(
        size: size,
        seriesList: seriesList,
        visibleRange: visibleRange,
        lifeEvents: lifeEvents,
      ),
      spendRate: spendRate,
      valueKind: valueKind,
    ).paint();
  }

  @override
  bool shouldRepaint(covariant CategoryTrendPainter oldDelegate) =>
      seriesList != oldDelegate.seriesList ||
      visibleRange != oldDelegate.visibleRange ||
      lifeEvents != oldDelegate.lifeEvents ||
      spendRate != oldDelegate.spendRate ||
      valueKind != oldDelegate.valueKind;
}

/// One chart frame: canvas + date-range layout + value scale.
class _CategoryTrendChartFrame({
  required final Canvas canvas,
  required final CategoryTrendPlot plot,
  required final TrendSpendRate spendRate,
  required final TrendValueKind valueKind,
}) {
  void paint() {
    _paintDashedValueTicksAndDateLanes();
    for (final series in plot.drawableSeries) {
      final samples = PaceLineSamples.alongPlot(series: series, plot: plot);
      if (series.percentileAreaFill) {
        samples.paintPercentileRankAsFillOpacity(canvas, plot);
      }
      samples.paintStroke(canvas);
    }
    for (final overlayLane in plot.overlayLanes) {
      overlayLane.paint(canvas, plot.chart);
    }
    _paintValueTickLabels();
  }

  void _paintDashedValueTicksAndDateLanes() {
    final gridPaint = Paint()
      ..color = EColors.border.withValues(alpha: 0.55)
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final tickPath = Path();
    for (final tickCents in plot.scale.tickCents) {
      if (tickCents <= 0) continue;
      tickPath.addPath(
        PaceLineSamples.dashedHorizontalPath(
          start: Offset(
            plot.chart.left,
            plot.scale.yForCents(tickCents, plot.chart),
          ),
          endX: plot.chart.right,
        ),
        Offset.zero,
      );
    }
    canvas.drawPath(tickPath, gridPaint);
    final chrome = EChartChrome(plot.chart);
    chrome.strokePlotEdges(canvas);
    chrome.paintYearBoundaryGuides(canvas);
    chrome.paintDateTicks(canvas);
  }

  void _paintValueTickLabels() {
    final axisStyle = EChartAxis.tickLabel;
    for (final tickCents in plot.scale.tickCents) {
      final label = formatAxisCents(
        valueKind == TrendValueKind.pace
            ? tickCents / spendRate.annualDivisor
            : tickCents,
      );
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: axisStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelY =
          plot.scale.yForCents(tickCents, plot.chart) - textPainter.height / 2;
      textPainter.paint(
        canvas,
        Offset(
          plot.chart.left - textPainter.width - 4,
          labelY.clamp(
            plot.chart.top - 2,
            plot.chart.bottom - textPainter.height,
          ),
        ),
      );
    }
  }
}
