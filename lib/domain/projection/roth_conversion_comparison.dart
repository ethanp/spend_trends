import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/domain/taxes/federal_income_tax.dart';
import 'package:spend_trends/domain/taxes/filing_status.dart';

/// Each Roth conversion choice run on the same start, life plan, and
/// assumptions, so only the drawdown differs.
class RothConversionComparison(final RetirementProjection projection) {
  /// Filling higher brackets than this converts at rates retirement never
  /// pays.
  static const _highestBracketCompared = 24;

  /// Heirs empty an inherited traditional account within ten years.
  static const _inheritedDistributionYears = 10;

  late final List<RothConversionOutcome> outcomes = [
    null,
    for (final int ratePercent
        in projection.assumptions.filingStatus.fillableBracketPercents)
      if (ratePercent <= _highestBracketCompared) ratePercent,
  ].mapL(_outcomeFilling);

  RothConversionOutcome _outcomeFilling(int? bracketPercent) {
    final RetirementProjection filled =
        bracketPercent == projection.assumptions.rothConversionBracketPercent
        ? projection
        : RetirementProjection(
            start: projection.start,
            lifePlan: projection.lifePlan,
            assumptions: projection.assumptions.merged({
              'rothConversionBracketPercent': bracketPercent,
            }),
          );
    final ProjectionYear? lastYear = filled.years.lastOrNull;
    return RothConversionOutcome(
      bracketPercent: bracketPercent,
      lifetimeTaxesPresentValue: _presentValueOfTaxes(filled.years),
      leftToHeirs: lastYear == null ? 0 : _afterHeirsTax(lastYear),
      earliestRetirementAge: filled.earliestRetirementAge,
    );
  }

  /// Each year's tax discounted at the real return: tax paid early also
  /// costs what it would have grown to, so this ranks the same way as
  /// [RothConversionOutcome.leftToHeirs].
  double _presentValueOfTaxes(List<ProjectionYear> years) {
    final double growthFactor =
        1 + projection.assumptions.realReturnPercent / 100;
    var presentValue = 0.0;
    for (var yearIndex = 0; yearIndex < years.length; yearIndex++) {
      presentValue +=
          years[yearIndex].taxes / math.pow(growthFactor, yearIndex + 1);
    }
    return presentValue;
  }

  /// Taxable gets a stepped-up basis and Roth passes tax-free; traditional
  /// is taxed as a single heir with no other income draws it evenly.
  double _afterHeirsTax(ProjectionYear lastYear) {
    if (lastYear.liquid <= 0) return lastYear.liquid;
    const heirsTax = FederalIncomeTax(filingStatus: FilingStatus.single);
    final double yearlyDraw =
        lastYear.traditional / _inheritedDistributionYears;
    return lastYear.liquid -
        _inheritedDistributionYears *
            heirsTax.billFor(YearIncome(ordinaryIncome: yearlyDraw)).total;
  }
}

/// What one conversion choice leads to, today's dollars.
class const RothConversionOutcome({
  /// Null: no conversions.
  required final int? bracketPercent,

  /// Federal tax and penalties over every projected year, discounted to
  /// today at the real return.
  required final double lifetimeTaxesPresentValue,

  /// Liquid savings at the end age after the tax heirs would pay.
  required final double leftToHeirs,
  required final int? earliestRetirementAge,
}) {
  String get label => bracketPercent == null ? 'None' : 'Fill $bracketPercent%';
}
