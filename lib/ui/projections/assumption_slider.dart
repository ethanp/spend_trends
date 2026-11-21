import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/projection/assumption_sweep.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/ui/projections/projections_providers.dart';

/// One assumption as a slider: its range and step, and how a value reads.
class const AssumptionSlider({
  required final String label,
  required final AssumptionSweepRange range,
  required final String Function(double value) caption,

  /// For an override: the actual figure over the last 365 days, used
  /// while the override is unset.
  final double? actualValue,
}) {
  /// Thumb overlay radius: the track (and the line under it) is inset by it.
  static const _trackInset = 10.0;

  String get _assumptionKey => range.assumptionKey;

  /// Label, slider, and value. Under the slider, a line traces the result
  /// (the headline's) across the slider's whole range, with a dot where the
  /// slider sits. Dragging re-runs the projection as you go; letting go
  /// saves.
  ELabeledControlRow rowFor(RetirementProjection projection) {
    return ELabeledControlRow.slider(
      label: label,
      caption: actualValue == null
          ? null
          : _ActualOrOverrideCaption(
              assumptionKey: _assumptionKey,
              isOverridden: _setValueIn(projection) != null,
            ),
      slider: _AssumptionSliderControl(
        key: ValueKey(_assumptionKey),
        slider: this,
        shownValue: _shownValueIn(projection),
      ),
      valueText: caption(_shownValueIn(projection)),
      below: _AssumptionSweepLine(
        slider: this,
        shownValue: _shownValueIn(projection),
        currentOutcome: _currentOutcomeIn(projection),
      ),
    );
  }

  /// Null only for an unset override.
  num? _setValueIn(RetirementProjection projection) =>
      projection.assumptions.toJson()[_assumptionKey] as num?;

  double _shownValueIn(RetirementProjection projection) =>
      (_setValueIn(projection)?.toDouble() ?? actualValue ?? range.min).clamp(
        range.min,
        range.max,
      );

  /// The result the current value gives, from the projection on screen;
  /// places the dot.
  int? _currentOutcomeIn(RetirementProjection projection) =>
      switch (range.outcomeKind) {
        SweepOutcomeKind.investingPercentNeeded =>
          projection.savingsTarget?.requiredInvestingPercent,
        SweepOutcomeKind.earliestRetirementAge =>
          projection.earliestRetirementAge,
      };

  /// Snapped to the step; whole-number assumptions are stored as ints.
  Object _stored(double value) {
    final double snapped = (value / range.step).round() * range.step;
    if (range.step >= 1) return snapped.round();
    return double.parse(snapped.toStringAsFixed(1));
  }
}

/// "last 365 days" while the actual figure is in use; once overridden,
/// "use actual", which clears the override.
class const _ActualOrOverrideCaption({
  required final String assumptionKey,
  required final bool isOverridden,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isOverridden) return const Text('last 365 days');
    return GestureDetector(
      onTap: () => ref
          .read(projectionAssumptionDraftsProvider.notifier)
          .release(assumptionKey, null),
      child: const Text(
        'use actual',
        style: TextStyle(color: EColors.accentGlow),
      ),
    );
  }
}

class const _AssumptionSliderControl({
  super.key,
  required final AssumptionSlider slider,
  required final double shownValue,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProjectionAssumptionDrafts drafts = ref.read(
      projectionAssumptionDraftsProvider.notifier,
    );
    final AssumptionSweepRange range = slider.range;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: AssumptionSlider._trackInset,
        ),
        tickMarkShape: SliderTickMarkShape.noTickMark,
      ),
      child: SizedBox(
        height: 18,
        child: Slider(
          value: shownValue,
          min: range.min,
          max: range.max,
          divisions: ((range.max - range.min) / range.step).round(),
          onChanged: (value) =>
              drafts.drag(slider._assumptionKey, slider._stored(value)),
          onChangeEnd: (value) =>
              drafts.release(slider._assumptionKey, slider._stored(value)),
        ),
      ),
    );
  }
}

class const _AssumptionSweepLine({
  required final AssumptionSlider slider,
  required final double shownValue,
  required final int? currentOutcome,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<SweepPoint>? sweepPoints = ref
        .watch(assumptionSweepProvider(slider.range))
        .value;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AssumptionSlider._trackInset,
      ),
      child: SizedBox(
        height: 16,
        width: double.infinity,
        child: sweepPoints == null
            ? null
            : CustomPaint(
                painter: _SweepLinePainter(
                  points: sweepPoints,
                  range: slider.range,
                  currentValue: shownValue,
                  currentOutcome: currentOutcome,
                ),
              ),
      ),
    );
  }
}

/// The result across the slider's range as a stepped line (higher is worse:
/// more to invest, or a later retirement), and a dot at the current value.
class _SweepLinePainter({
  required final List<SweepPoint> points,
  required final AssumptionSweepRange range,
  required final double currentValue,
  required final int? currentOutcome,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outcomes = [
      for (final point in points)
        if (point.outcome != null) point.outcome!,
    ];
    if (outcomes.isEmpty) return;
    final lowest = outcomes.reduce(math.min);
    final highest = outcomes.reduce(math.max);
    double xOf(double value) =>
        (value - range.min) / (range.max - range.min) * size.width;
    double yOf(int outcome) => highest == lowest
        ? size.height / 2
        : size.height - (outcome - lowest) / (highest - lowest) * size.height;

    canvas.drawPath(
      _steppedLine(xOf, yOf),
      Paint()
        ..color = EColors.textMuted
        ..strokeWidth = 1.25
        ..style = PaintingStyle.stroke,
    );
    final outcome = currentOutcome;
    if (outcome == null) return;
    canvas.drawCircle(
      Offset(xOf(currentValue), yOf(outcome.clamp(lowest, highest))),
      3,
      Paint()..color = EColors.accentGlow,
    );
  }

  /// Each sample holds its result until halfway to the next; a sample with
  /// no result breaks the line.
  Path _steppedLine(
    double Function(double value) xOf,
    double Function(int outcome) yOf,
  ) {
    final path = Path();
    var drawing = false;
    for (var index = 0; index < points.length; index++) {
      final outcome = points[index].outcome;
      if (outcome == null) {
        drawing = false;
        continue;
      }
      final x = xOf(points[index].value);
      final left = index == 0 ? x : (xOf(points[index - 1].value) + x) / 2;
      final right = index == points.length - 1
          ? x
          : (x + xOf(points[index + 1].value)) / 2;
      final y = yOf(outcome);
      if (drawing) {
        path.lineTo(left, y);
      } else {
        path.moveTo(left, y);
        drawing = true;
      }
      path.lineTo(right, y);
    }
    return path;
  }

  @override
  bool shouldRepaint(_SweepLinePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.currentValue != currentValue ||
      oldDelegate.currentOutcome != currentOutcome;
}
