import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/features/trends/category_trend_plot.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/pace_line_samples.dart';
import 'package:spend_trends/theme/draw/date_range_band.dart';
import 'package:spend_trends/theme/finance_colors.dart';

class CategoryTrendPainter({
  required final List<CategoryTrendSeries> seriesList,
  final List<LifeEvent> lifeEvents = const [],
  final StayChain? housingChain,
  final StayChain? jobChain,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (!seriesList.any((series) => series.canPlot)) return;

    _CategoryTrendChartFrame(
      canvas: canvas,
      plot: CategoryTrendPlot.from(
        size: size,
        seriesList: seriesList,
        housingChain: housingChain,
        jobChain: jobChain,
        lifeEvents: lifeEvents,
      ),
      lifeEvents: lifeEvents,
      housingChain: housingChain,
      jobChain: jobChain,
    ).paint();
  }

  @override
  bool shouldRepaint(covariant CategoryTrendPainter oldDelegate) =>
      seriesList != oldDelegate.seriesList ||
      lifeEvents != oldDelegate.lifeEvents ||
      housingChain != oldDelegate.housingChain ||
      jobChain != oldDelegate.jobChain;
}

/// One chart frame: canvas + date-range layout + value scale.
class _CategoryTrendChartFrame({
  required final Canvas canvas,
  required final CategoryTrendPlot plot,
  required final List<LifeEvent> lifeEvents,
  required final StayChain? housingChain,
  required final StayChain? jobChain,
}) {
  static const _labelFontSize = 14.0;
  static const _labelStackStep = 18.0;
  static const _labelStackGapPx = 6.0;
  static const _eraEdgeAlpha = 0.4;
  static const _eraEdgeStroke = 1.0;

  double _laneTop(int laneIndex) =>
      laneIndex * CategoryTrendPlot.overlayLaneHeight;

  double _laneBottom(int laneIndex) =>
      _laneTop(laneIndex) + CategoryTrendPlot.overlayLaneHeight;

  double _laneLabelY(int laneIndex) => _laneTop(laneIndex) + 4;

  /// Room from the label's anchor to the right edge of the plot.
  double _labelRoom(double anchorX) {
    final room = plot.chart.right - anchorX - 4;
    if (room < 48) return 48;
    return room;
  }

  int? _laneForKind(LifeChainKind kind) => switch (kind) {
    LifeChainKind.housing => plot.housingLane,
    LifeChainKind.job => plot.jobLane,
  };

  void paint() {
    _paintDashedValueTicksAndDateLanes();
    for (final series in plot.drawableSeries) {
      final samples = PaceLineSamples.alongPlot(series: series, plot: plot);
      if (series.percentileAreaFill) {
        samples.paintPercentileRankAsFillOpacity(canvas, plot);
      }
      samples.paintStroke(canvas);
    }

    final chartMin = plot.chart.start.startOfDay;
    final chartMax = plot.chart.end.startOfDay;
    _paintAlternatingStayEras(
      kind: LifeChainKind.housing,
      chain: housingChain,
      segments: _visibleStaySegments(
        housingChain,
        chartMin: chartMin,
        chartMax: chartMax,
      ),
    );
    _paintAlternatingStayEras(
      kind: LifeChainKind.job,
      chain: jobChain,
      segments: _visibleStaySegments(
        jobChain,
        chartMin: chartMin,
        chartMax: chartMax,
      ),
    );
    _paintLifeEventSpansAndPointTicks(
      _visibleLifeEvents(chartMin: chartMin, chartMax: chartMax),
    );
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

  List<ChainStaySegment> _visibleStaySegments(
    StayChain? chain, {
    required DateTime chartMin,
    required DateTime chartMax,
  }) {
    if (chain == null || chain.isEmpty) return const [];
    return [
      for (final segment in chain.segments)
        if (segment.intersectsChart(
          chartMinDate: chartMin,
          chartMaxDate: chartMax,
        ))
          segment,
    ];
  }

  List<LifeEvent> _visibleLifeEvents({
    required DateTime chartMin,
    required DateTime chartMax,
  }) {
    return [
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
  }

  void _paintAlternatingStayEras({
    required LifeChainKind kind,
    required StayChain? chain,
    required List<ChainStaySegment> segments,
  }) {
    if (segments.isEmpty) return;
    final laneIndex = _laneForKind(kind);
    if (laneIndex == null) return;
    final fillTop = _laneTop(laneIndex);
    final fillBottom = _laneBottom(laneIndex);
    final baseLabelY = _laneLabelY(laneIndex);
    final chartMax = plot.chart.end.startOfDay;
    final chainSegments = chain?.segments ?? const <ChainStaySegment>[];
    final eraIndexByStayId = {
      for (var eraIndex = 0; eraIndex < chainSegments.length; eraIndex++)
        chainSegments[eraIndex].stay.id: eraIndex,
    };

    final labelLeftXs = <double>[];
    final labelWidths = <double>[];
    final textPainters = <TextPainter>[];
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final eraIndex = eraIndexByStayId[segment.stay.id] ?? index;
      final eraAccent = kind.trendEraAccent(eraIndex);
      final labelAnchorX = dateRangeLabelAnchorX(
        plot: plot.chart,
        rangeStart: segment.rangeStart,
      );
      final textPainter = TextPainter(
        text: _stayChainLabelSpan(
          kind: kind,
          label: segment.stay.label,
          color: eraAccent,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: _labelRoom(labelAnchorX));
      final labelX = (labelAnchorX + 3).clamp(
        plot.chart.left,
        plot.chart.right - textPainter.width,
      );
      labelLeftXs.add(labelX);
      labelWidths.add(textPainter.width);
      textPainters.add(textPainter);
    }
    final stackRows = _withinLaneStackRows(
      labelLeftXs: labelLeftXs,
      labelWidths: labelWidths,
    );

    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final eraIndex = eraIndexByStayId[segment.stay.id] ?? index;
      final eraAccent = kind.trendEraAccent(eraIndex);
      final fillStyle = eraIndex.isEven
          ? DateRangeBandFillStyle.solid
          : DateRangeBandFillStyle.hatch;
      final edgePaint = Paint()
        ..color = eraAccent.withValues(alpha: _eraEdgeAlpha)
        ..strokeWidth = _eraEdgeStroke;

      final geometry = dateRangeBandGeometry(
        plot: plot.chart,
        rangeStart: segment.rangeStart,
        rangeEnd: segment.effectiveEndOn(chartMax),
        showLeftEdge: true,
        showRightEdge: segment.rangeEnd != null,
      );
      if (geometry != null) {
        paintDateRangeBand(
          canvas,
          plot: plot.chart,
          geometry: geometry,
          edgePaint: edgePaint,
          fillColor: eraAccent,
          fillStyle: fillStyle,
          fillAlpha: 0.12,
          fillTop: fillTop,
          fillBottom: fillBottom,
          edgeTop: plot.chart.top,
          edgeBottom: plot.chart.bottom,
        );
      }

      final labelY = baseLabelY + stackRows[index] * _labelStackStep;
      textPainters[index].paint(canvas, Offset(labelLeftXs[index], labelY));
    }
  }

  /// Greedy vertical rows inside one overlay lane when label boxes collide on X.
  List<int> _withinLaneStackRows({
    required List<double> labelLeftXs,
    required List<double> labelWidths,
  }) {
    final order = [
      for (var index = 0; index < labelLeftXs.length; index++) index,
    ]..sort((left, right) => labelLeftXs[left].compareTo(labelLeftXs[right]));
    final stackRows = List<int>.filled(labelLeftXs.length, 0);
    final lastRightByRow = <int, double>{};
    for (final index in order) {
      final labelLeft = labelLeftXs[index];
      final labelRight = labelLeft + labelWidths[index];
      var row = 0;
      while (true) {
        final previousRight = lastRightByRow[row];
        if (previousRight == null ||
            labelLeft >= previousRight + _labelStackGapPx) {
          stackRows[index] = row;
          lastRightByRow[row] = labelRight;
          break;
        }
        row++;
      }
    }
    return stackRows;
  }

  TextSpan _stayChainLabelSpan({
    required LifeChainKind kind,
    required String label,
    required Color color,
  }) {
    final labelStyle = TextStyle(
      color: color,
      fontSize: _labelFontSize,
      fontWeight: FontWeight.w600,
      height: 1,
    );
    if (kind != LifeChainKind.housing) {
      return TextSpan(text: label, style: labelStyle);
    }
    const houseIcon = Icons.home;
    return TextSpan(
      children: [
        TextSpan(
          text: String.fromCharCode(houseIcon.codePoint),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontFamily: houseIcon.fontFamily,
            package: houseIcon.fontPackage,
            height: 1,
          ),
        ),
        TextSpan(text: ' $label', style: labelStyle),
      ],
    );
  }

  void _paintLifeEventSpansAndPointTicks(List<LifeEvent> markersInRange) {
    if (markersInRange.isEmpty) return;
    final lifeEventLane = plot.lifeEventLane;
    if (lifeEventLane == null) return;
    final chartMax = plot.chart.end.startOfDay;
    final fillTop = _laneTop(lifeEventLane);
    final fillBottom = _laneBottom(lifeEventLane);
    final baseLabelY = _laneLabelY(lifeEventLane);

    final bandFillPaint = Paint()
      ..color = FinanceColors.accentSecondary.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final bandEdgePaint = Paint()
      ..color = FinanceColors.accentSecondary.withValues(alpha: _eraEdgeAlpha)
      ..strokeWidth = _eraEdgeStroke;
    final linePaint = Paint()
      ..color = FinanceColors.accentSecondary.withValues(alpha: _eraEdgeAlpha)
      ..strokeWidth = _eraEdgeStroke
      ..style = PaintingStyle.stroke;
    final tickPath = Path();

    final labelLeftXs = <double>[];
    final labelWidths = <double>[];
    final textPainters = <TextPainter>[];
    for (final lifeEvent in markersInRange) {
      final labelAnchorX = dateRangeLabelAnchorX(
        plot: plot.chart,
        rangeStart: lifeEvent.startedOn,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: lifeEvent.title,
          style: const TextStyle(
            color: FinanceColors.accentSecondary,
            fontSize: _labelFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: _labelRoom(labelAnchorX));
      final labelX = (labelAnchorX + 3).clamp(
        plot.chart.left,
        plot.chart.right - textPainter.width,
      );
      labelLeftXs.add(labelX);
      labelWidths.add(textPainter.width);
      textPainters.add(textPainter);
    }
    final stackRows = _withinLaneStackRows(
      labelLeftXs: labelLeftXs,
      labelWidths: labelWidths,
    );

    for (
      var markerIndex = 0;
      markerIndex < markersInRange.length;
      markerIndex++
    ) {
      final lifeEvent = markersInRange[markerIndex];
      final labelAnchorX = dateRangeLabelAnchorX(
        plot: plot.chart,
        rangeStart: lifeEvent.startedOn,
      );

      if (lifeEvent.isPoint) {
        tickPath.addPath(
          _dashedVerticalTickPath(
            Offset(labelAnchorX, plot.chart.top),
            Offset(labelAnchorX, plot.chart.bottom),
          ),
          Offset.zero,
        );
      } else {
        final geometry = dateRangeBandGeometry(
          plot: plot.chart,
          rangeStart: lifeEvent.startedOn,
          rangeEnd: lifeEvent.effectiveEndOn(chartMax),
          showLeftEdge: true,
          showRightEdge: lifeEvent.isClosedRange,
        );
        if (geometry != null) {
          paintDateRangeBand(
            canvas,
            plot: plot.chart,
            geometry: geometry,
            fillPaint: bandFillPaint,
            edgePaint: bandEdgePaint,
            fillTop: fillTop,
            fillBottom: fillBottom,
            edgeTop: plot.chart.top,
            edgeBottom: plot.chart.bottom,
          );
        }
      }

      final labelY = baseLabelY + stackRows[markerIndex] * _labelStackStep;
      textPainters[markerIndex].paint(
        canvas,
        Offset(labelLeftXs[markerIndex], labelY),
      );
    }
    canvas.drawPath(tickPath, linePaint);
  }

  Path _dashedVerticalTickPath(Offset start, Offset end) {
    const dashLength = 4.0;
    const gapLength = 3.0;
    final height = end.dy - start.dy;
    final path = Path();
    if (height <= 0) return path;
    var drawn = 0.0;
    var drawingDash = true;
    while (drawn < height) {
      final step = drawingDash ? dashLength : gapLength;
      final next = drawn + step < height ? drawn + step : height;
      if (drawingDash) {
        path
          ..moveTo(start.dx, start.dy + drawn)
          ..lineTo(start.dx, start.dy + next);
      }
      drawn = next;
      drawingDash = !drawingDash;
    }
    return path;
  }

  void _paintValueTickLabels() {
    final axisStyle = EChartAxis.tickLabel;
    for (final tickCents in plot.scale.tickCents) {
      final label = formatAxisCents(tickCents);
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
