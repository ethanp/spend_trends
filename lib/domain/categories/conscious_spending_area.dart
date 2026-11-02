import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';

/// Ramit Sethi's conscious-spending buckets (share of pay: take-home plus
/// payroll contributions, as Ramit adds 401(k) back), minus savings goals:
/// planned expenses come straight from paychecks here, so there is no
/// sinking fund to measure. Each of Ramit's ranges is one round target near
/// its middle (50–60% → 55%, 20–35% → 30%).
enum ConsciousSpendingArea({
  required final ConsciousSpendingGuideline ramitGuideline,
  final String? _displayName,
}) {
  fixedCosts(
    ramitGuideline: ConsciousSpendingGuideline(
      targetPercent: 55,
      betterSide: GuidelineBetterSide.lower,
    ),
  ),
  investments(
    ramitGuideline: ConsciousSpendingGuideline(
      targetPercent: 10,
      betterSide: GuidelineBetterSide.higher,
    ),
  ),
  guiltFree(
    ramitGuideline: ConsciousSpendingGuideline(
      targetPercent: 30,
      betterSide: GuidelineBetterSide.lower,
    ),
    displayName: 'Guilt-free',
  );

  String get displayName => _displayName ?? nameAsCapitalizedWords;

  String get storageValue => name;

  static ConsciousSpendingArea? fromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final area in values) {
      if (area.name == value) return area;
    }
    return null;
  }
}

/// Which side of a guideline's target beats it.
enum GuidelineBetterSide() {
  higher,
  lower,

  /// Any distance from the target misses it.
  neither,
}

/// A target share of pay, and which side of it is better. Spending areas are
/// better lower (the FIRE goal is a bigger gap between pay and spending);
/// investing is better higher; savings aims at exactly its target.
class const ConsciousSpendingGuideline({
  required final int targetPercent,
  required final GuidelineBetterSide betterSide,

  /// Where a non-Ramit target came from, e.g. `retire at 45`.
  final String? reason,
}) {
  /// Points past the target at which [score] saturates.
  static const _fullScorePoints = 20;

  /// Savings, the pay left after the three areas, aims at 0: cash should
  /// neither pile up nor drain on net over time.
  static const savings = ConsciousSpendingGuideline(
    targetPercent: 0,
    betterSide: GuidelineBetterSide.neither,
  );

  /// Ramit's target, except Investments, which uses what retiring at the
  /// planned age needs once a projection exists.
  factory forArea(
    ConsciousSpendingArea area, {
    RetirementSavingsTarget? retirementTarget,
  }) {
    if (area != ConsciousSpendingArea.investments || retirementTarget == null) {
      return area.ramitGuideline;
    }
    return ConsciousSpendingGuideline(
      targetPercent: retirementTarget.requiredInvestingPercent,
      betterSide: GuidelineBetterSide.higher,
      reason: 'retire at ${retirementTarget.retirementAge}',
    );
  }

  String get targetLabel => '$targetPercent%';

  /// At the target or on its better side.
  bool isMetBy(int percent) => switch (betterSide) {
    GuidelineBetterSide.higher => percent >= targetPercent,
    GuidelineBetterSide.lower => percent <= targetPercent,
    GuidelineBetterSide.neither => percent == targetPercent,
  };

  /// How far [percent] beats (toward 1) or misses (toward −1) the target:
  /// 0 on it, ±1 at [_fullScorePoints] or more past it.
  double score(int percent) {
    final int pointsAboveTarget = percent - targetPercent;
    final int pointsBetter = switch (betterSide) {
      GuidelineBetterSide.higher => pointsAboveTarget,
      GuidelineBetterSide.lower => -pointsAboveTarget,
      GuidelineBetterSide.neither => -pointsAboveTarget.abs(),
    };
    return (pointsBetter / _fullScorePoints).clamp(-1.0, 1.0);
  }

  /// The target applied to [payCents].
  int impliedCents(int payCents) => (payCents * targetPercent / 100).round();
}
