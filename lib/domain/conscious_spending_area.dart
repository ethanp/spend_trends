import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';

/// Ramit Sethi's conscious-spending buckets (share of take-home pay), minus
/// savings goals: planned expenses come straight from paychecks here, so
/// there is no sinking fund to measure.
enum ConsciousSpendingArea({
  required final ConsciousSpendingGuideline ramitGuideline,
  final String? _displayName,
}) {
  fixedCosts(
    ramitGuideline: ConsciousSpendingGuideline(
      minPercent: 50,
      maxPercent: 60,
      higherIsBetter: false,
    ),
  ),
  investments(
    ramitGuideline: ConsciousSpendingGuideline(
      minPercent: 10,
      maxPercent: 10,
      higherIsBetter: true,
    ),
  ),
  guiltFree(
    ramitGuideline: ConsciousSpendingGuideline(
      minPercent: 20,
      maxPercent: 35,
      higherIsBetter: false,
    ),
    displayName: 'Guilt-free',
  );

  String get displayName => _displayName ?? nameAsCapitalizedWords;

  String get storageValue => name;

  /// Rounded share of [incomeCents], or null when there is no take-home pay.
  int? percentOfIncome({required int areaCents, required int incomeCents}) {
    if (incomeCents <= 0) return null;
    return (areaCents / incomeCents * 100).round();
  }

  static ConsciousSpendingArea? fromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final area in values) {
      if (area.name == value) return area;
    }
    return null;
  }
}

/// A target share of take-home pay for one area, and which way beats it.
/// Spending areas are better lower (the FIRE goal is a bigger gap between
/// take-home and spending); investing is better higher.
class const ConsciousSpendingGuideline({
  required final int minPercent,
  required final int maxPercent,
  required final bool higherIsBetter,

  /// Where a non-Ramit target came from, e.g. `retire at 45`.
  final String? reason,
}) {
  /// Points past the guideline at which [score] saturates.
  static const _fullScorePoints = 20;

  /// Ramit's range, except Investments, which uses what retiring at the
  /// planned age needs once a projection exists.
  factory forArea(
    ConsciousSpendingArea area, {
    RetirementSavingsTarget? retirementTarget,
  }) {
    if (area != ConsciousSpendingArea.investments || retirementTarget == null) {
      return area.ramitGuideline;
    }
    final percent = retirementTarget.requiredInvestingPercent;
    return ConsciousSpendingGuideline(
      minPercent: percent,
      maxPercent: percent,
      higherIsBetter: true,
      reason: 'retire at ${retirementTarget.retirementAge}',
    );
  }

  /// e.g. `50–60%`, `10%`, or `≥31%` for a one-sided target.
  String get rangeLabel {
    if (minPercent != maxPercent) return '$minPercent–$maxPercent%';
    if (reason == null) return '$minPercent%';
    return higherIsBetter ? '≥$minPercent%' : '≤$minPercent%';
  }

  bool contains(int percent) => higherIsBetter && reason != null
      ? percent >= minPercent
      : percent >= minPercent && percent <= maxPercent;

  /// How far [percent] beats (toward 1) or misses (toward −1) the guideline:
  /// 0 inside the range, ±1 at [_fullScorePoints] or more past its edge.
  double score(int percent) {
    final int pointsAboveRange = percent > maxPercent
        ? percent - maxPercent
        : percent < minPercent
        ? percent - minPercent
        : 0;
    final pointsBetter = higherIsBetter ? pointsAboveRange : -pointsAboveRange;
    return (pointsBetter / _fullScorePoints).clamp(-1.0, 1.0);
  }

  /// Guideline percents applied to annual take-home [incomeCents].
  String impliedTakeHomeLabel(int incomeCents) {
    if (incomeCents <= 0) return '—';
    final lowCents = (incomeCents * minPercent / 100).round();
    final highCents = (incomeCents * maxPercent / 100).round();
    final lowLabel = formatCentsWholeDollars(lowCents);
    if (lowCents == highCents) return lowLabel;
    return '$lowLabel–${formatCentsWholeDollars(highCents)}';
  }
}
