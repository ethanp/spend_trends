import 'package:spend_trends/domain/projection/retirement_projection.dart';

/// The result a sweep reads off each re-run projection.
enum SweepOutcomeKind() {
  /// Share of take-home to invest to retire at the planned age.
  investingPercentNeeded,

  /// Earliest age savings last to the end of the plan.
  earliestRetirementAge,
}

/// One sampled value of the swept assumption and the result it produced;
/// a null [outcome] means no retirement age works.
class const SweepPoint({required final double value, final int? outcome});

/// How one result changes as a single assumption moves across its range,
/// every other assumption held where it is: the landscape a slider drags
/// through.
class AssumptionSweep({
  required final RetirementProjection projection,
  required final String assumptionKey,
  required final double min,
  required final double max,

  /// The slider's step; samples land on its values.
  required final double step,
  required final SweepOutcomeKind outcomeKind,
}) {
  /// Enough points to read the curve without re-running hundreds of
  /// projections per slider.
  static const _maxSampleCount = 36;

  late final List<SweepPoint> points = () {
    final stepCount = ((max - min) / step).round();
    final stride = (stepCount / (_maxSampleCount - 1)).ceil();
    return [
      for (var stepIndex = 0; stepIndex < stepCount; stepIndex += stride)
        _pointAt(min + stepIndex * step),
      _pointAt(max),
    ];
  }();

  SweepPoint _pointAt(double value) {
    final sampled = RetirementProjection(
      start: projection.start,
      lifePlan: projection.lifePlan,
      assumptions: projection.assumptions.merged({
        assumptionKey: _jsonValue(value),
      }),
    );
    return SweepPoint(
      value: value,
      outcome: switch (outcomeKind) {
        SweepOutcomeKind.investingPercentNeeded =>
          sampled.savingsTarget?.requiredInvestingPercent,
        SweepOutcomeKind.earliestRetirementAge => sampled.earliestRetirementAge,
      },
    );
  }

  /// Whole-number assumptions are stored as ints.
  Object _jsonValue(double value) =>
      projection.assumptions.toJson()[assumptionKey] is double
      ? value
      : value.round();
}
