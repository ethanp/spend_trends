import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/theme/draw/date_range_band.dart';
import 'package:spend_trends/theme/life_event_lane_color.dart';

/// One overlay lane above the Trends plot: its life events' date ranges,
/// titled in the Y-axis gutter. Labels that collide on X stack into extra
/// rows, and the lane grows to hold every row.
class TrendOverlayLane._(
  final LifeEventLane lifeEventLane,
  final double top,
  final TextPainter _titlePainter,
  final List<_StackedEraLabel> _stackedLabels, {
  required final int rowCount,
}) {
  static const _labelFontSize = 14.0;
  static const _labelRowStep = 18.0;
  static const _labelTopInset = 4.0;
  static const _labelBottomInset = 4.0;
  static const _labelGapPx = 6.0;
  static const _minLabelRoom = 48.0;
  static const _titleFontSize = 10.0;
  static const _titleGutterGap = 4.0;
  static const _eraEdgeAlpha = 0.4;
  static const _eraEdgeStroke = 1.0;

  /// Lays out the labels of [visibleLifeEvents] (oldest first, one era each)
  /// along [xAxis] (only its X mapping is read) below [top].
  factory stackedBelow({
    required double top,
    required EChartPlot xAxis,
    required LifeEventLane lifeEventLane,
    required List<LifeEvent> visibleLifeEvents,
  }) {
    final placedLabels = [
      for (var eraIndex = 0; eraIndex < visibleLifeEvents.length; eraIndex++)
        _placedAlong(
          xAxis,
          lifeEventLane: lifeEventLane,
          lifeEvent: visibleLifeEvents[eraIndex],
          eraIndex: eraIndex,
        ),
    ]..sort((left, right) => left.leftX.compareTo(right.leftX));
    final lastRightByRow = <double>[];
    final stackedLabels = <_StackedEraLabel>[];
    for (final placedLabel in placedLabels) {
      var row = 0;
      while (row < lastRightByRow.length &&
          placedLabel.leftX < lastRightByRow[row] + _labelGapPx) {
        row++;
      }
      final labelRight = placedLabel.leftX + placedLabel.textPainter.width;
      if (row == lastRightByRow.length) {
        lastRightByRow.add(labelRight);
      } else {
        lastRightByRow[row] = labelRight;
      }
      stackedLabels.add(
        _StackedEraLabel(
          lifeEvent: placedLabel.lifeEvent,
          eraIndex: placedLabel.eraIndex,
          textPainter: placedLabel.textPainter,
          offset: Offset(
            placedLabel.leftX,
            top + _labelTopInset + row * _labelRowStep,
          ),
        ),
      );
    }
    final titlePainter = TextPainter(
      text: TextSpan(
        text: lifeEventLane.title,
        style: TextStyle(
          color: lifeEventLane.color,
          fontSize: _titleFontSize,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: xAxis.left - _titleGutterGap);
    return TrendOverlayLane._(
      lifeEventLane,
      top,
      titlePainter,
      stackedLabels,
      rowCount: lastRightByRow.length,
    );
  }

  static _PlacedEraLabel _placedAlong(
    EChartPlot xAxis, {
    required LifeEventLane lifeEventLane,
    required LifeEvent lifeEvent,
    required int eraIndex,
  }) {
    final anchorX = dateRangeLabelAnchorX(
      plot: xAxis,
      rangeStart: lifeEvent.startedOn,
    );
    final roomToPlotEdge = xAxis.right - anchorX - 4;
    final textPainter =
        TextPainter(
          text: TextSpan(
            text: lifeEvent.title,
            style: TextStyle(
              color: lifeEventLane.eraAccent(eraIndex),
              fontSize: _labelFontSize,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(
          maxWidth: roomToPlotEdge < _minLabelRoom
              ? _minLabelRoom
              : roomToPlotEdge,
        );
    return _PlacedEraLabel(
      lifeEvent: lifeEvent,
      eraIndex: eraIndex,
      textPainter: textPainter,
      leftX: (anchorX + 3).clamp(xAxis.left, xAxis.right - textPainter.width),
    );
  }

  double get bottom =>
      top + _labelTopInset + rowCount * _labelRowStep + _labelBottomInset;

  /// Each event's range as a lane band (alternating solid and hatch) with
  /// edges down through [plot], or a dashed tick through [plot] for a
  /// point-in-time event; then the gutter title, a hairline along the lane's
  /// bottom so adjacent lanes read apart, and the labels.
  void paint(Canvas canvas, EChartPlot plot) {
    final ticksPath = Path();
    for (final stackedLabel in _stackedLabels) {
      final lifeEvent = stackedLabel.lifeEvent;
      if (lifeEvent.isPoint) {
        final tickX = dateRangeLabelAnchorX(
          plot: plot,
          rangeStart: lifeEvent.startedOn,
        );
        ticksPath.addPath(
          _dashedVerticalTickPath(
            Offset(tickX, plot.top),
            Offset(tickX, plot.bottom),
          ),
          Offset.zero,
        );
        continue;
      }
      _paintEraBand(canvas, plot, stackedLabel);
    }
    canvas.drawPath(
      ticksPath,
      Paint()
        ..color = lifeEventLane.color.withValues(alpha: _eraEdgeAlpha)
        ..strokeWidth = _eraEdgeStroke
        ..style = PaintingStyle.stroke,
    );
    _titlePainter.paint(
      canvas,
      Offset(
        plot.left - _titleGutterGap - _titlePainter.width,
        top + _labelTopInset + (_labelFontSize - _titleFontSize),
      ),
    );
    canvas.drawLine(
      Offset(0, bottom),
      Offset(plot.right, bottom),
      Paint()
        ..color = EColors.border.withValues(alpha: 0.55)
        ..strokeWidth = 0.75,
    );
    for (final stackedLabel in _stackedLabels) {
      stackedLabel.textPainter.paint(canvas, stackedLabel.offset);
    }
  }

  void _paintEraBand(
    Canvas canvas,
    EChartPlot plot,
    _StackedEraLabel stackedLabel,
  ) {
    final lifeEvent = stackedLabel.lifeEvent;
    final geometry = dateRangeBandGeometry(
      plot: plot,
      rangeStart: lifeEvent.startedOn,
      rangeEnd: lifeEvent.effectiveEndOn(plot.end.startOfDay),
      showLeftEdge: true,
      showRightEdge: lifeEvent.isClosedRange,
    );
    if (geometry == null) return;
    final eraAccent = lifeEventLane.eraAccent(stackedLabel.eraIndex);
    paintDateRangeBand(
      canvas,
      plot: plot,
      geometry: geometry,
      edgePaint: Paint()
        ..color = eraAccent.withValues(alpha: _eraEdgeAlpha)
        ..strokeWidth = _eraEdgeStroke,
      fillColor: eraAccent,
      fillStyle: stackedLabel.eraIndex.isEven
          ? DateRangeBandFillStyle.solid
          : DateRangeBandFillStyle.hatch,
      fillTop: top,
      fillBottom: bottom,
      edgeTop: plot.top,
      edgeBottom: plot.bottom,
    );
  }

  static Path _dashedVerticalTickPath(Offset start, Offset end) {
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
}

class const _PlacedEraLabel({
  required final LifeEvent lifeEvent,
  required final int eraIndex,
  required final TextPainter textPainter,
  required final double leftX,
});

class const _StackedEraLabel({
  required final LifeEvent lifeEvent,
  required final int eraIndex,
  required final TextPainter textPainter,
  required final Offset offset,
});
