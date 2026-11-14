import 'dart:math' as math;

import 'package:spend_trends/domain/taxes/filing_status.dart';
import 'package:spend_trends/domain/taxes/marketplace_coverage.dart';

/// One year's income as the federal return sees it, in today's dollars.
class const YearIncome({
  /// Wages, traditional distributions, Roth conversions, and Roth earnings
  /// taken early.
  final double ordinaryIncome = 0,

  /// Long-term gains and qualified dividends.
  final double longTermGains = 0,
  final double socialSecurityBenefits = 0,

  /// Traditional money and Roth earnings or unseasoned conversions taken
  /// before 59½: the 10% penalty applies on top of income tax.
  final double takenBeforePenaltyFreeAge = 0,

  /// Marketplace health coverage bought this year; its premium tax credit
  /// is settled on the return.
  final MarketplaceCoverage? marketplaceCoverage,
}) {
  /// AGI plus untaxed Social Security: what the premium tax credit reads.
  double get modifiedAgiForMarketplace =>
      ordinaryIncome + longTermGains + socialSecurityBenefits;

  YearIncome plus({
    double ordinaryIncome = 0,
    double longTermGains = 0,
    double takenBeforePenaltyFreeAge = 0,
  }) => YearIncome(
    ordinaryIncome: this.ordinaryIncome + ordinaryIncome,
    longTermGains: this.longTermGains + longTermGains,
    socialSecurityBenefits: socialSecurityBenefits,
    takenBeforePenaltyFreeAge:
        this.takenBeforePenaltyFreeAge + takenBeforePenaltyFreeAge,
    marketplaceCoverage: marketplaceCoverage,
  );
}

/// What a year's federal return owes, today's dollars.
class const IncomeTaxBill({
  required final double ordinaryIncomeTax,
  required final double capitalGainsTax,
  required final double earlyWithdrawalPenalty,
  final double premiumTaxCredit = 0,
}) {
  /// Negative when the premium tax credit is larger than the tax.
  double get total =>
      ordinaryIncomeTax +
      capitalGainsTax +
      earlyWithdrawalPenalty -
      premiumTaxCredit;
}

/// The federal income tax on a year's income: ordinary brackets after the
/// standard deduction, long-term gains stacked on top in the 0/15/20%
/// bands, the taxable part of Social Security, the early-withdrawal
/// penalty, and the marketplace premium tax credit.
///
/// The projection runs in today's dollars. Indexed numbers hold still;
/// the Social Security thresholds do not, so [priceLevel] (nominal dollars
/// per today's dollar that year) shrinks them.
class const FederalIncomeTax({
  required final FilingStatus filingStatus,
  final double priceLevel = 1,
  final bool filersAreSixtyFiveOrOlder = false,
}) {
  static const _earlyWithdrawalPenaltyRate = 0.10;
  static const _socialSecurityTaxRate = 0.062;

  /// 2026 Social Security wage base; indexed.
  static const _socialSecurityWageBase = 184500.0;
  static const _medicareTaxRate = 0.0145;
  static const _additionalMedicareTaxRate = 0.009;
  static const _fifteenPercent = 0.15;
  static const _twentyPercent = 0.20;

  IncomeTaxBill billFor(YearIncome income) {
    final TaxableIncome taxable = _taxableIncomeOf(income);
    return IncomeTaxBill(
      ordinaryIncomeTax: _ordinaryIncomeTaxOn(taxable.ordinary),
      capitalGainsTax: _gainsTaxStackedOn(taxable),
      earlyWithdrawalPenalty:
          income.takenBeforePenaltyFreeAge * _earlyWithdrawalPenaltyRate,
      premiumTaxCredit:
          income.marketplaceCoverage?.premiumTaxCreditAt(
            income.modifiedAgiForMarketplace,
          ) ??
          0,
    );
  }

  /// How much more ordinary income [income] can take and keep its premium
  /// tax credit; unlimited without marketplace coverage or once income is
  /// already past the credit.
  double ordinaryIncomeRoomKeepingPremiumTaxCredit(YearIncome income) {
    final MarketplaceCoverage? coverage = income.marketplaceCoverage;
    if (coverage == null) return double.infinity;
    final double room =
        coverage.creditIncomeLimit - income.modifiedAgiForMarketplace;
    return room < 0 ? double.infinity : room;
  }

  /// The wages on the return behind a year's [takeHome]: take-home is pay
  /// after income tax, Social Security and Medicare tax, and
  /// [payrollContributions] (pre-tax 401(k) and HSA, which still pay
  /// Social Security and Medicare tax).
  double taxableWagesBehindTakeHome(
    double takeHome, {
    required double payrollContributions,
  }) {
    if (takeHome <= 0) return 0;
    double takeHomeFrom(double taxableWages) =>
        taxableWages -
        billFor(YearIncome(ordinaryIncome: taxableWages)).total -
        _payrollTaxOn(taxableWages + payrollContributions);
    var below = takeHome;
    var above = takeHome * 3 + filingStatus.standardDeduction;
    while (above - below > 1) {
      final double middle = (below + above) / 2;
      if (takeHomeFrom(middle) < takeHome) {
        below = middle;
      } else {
        above = middle;
      }
    }
    return below;
  }

  double _payrollTaxOn(double grossWages) =>
      math.min(grossWages, _socialSecurityWageBase) * _socialSecurityTaxRate +
      grossWages * _medicareTaxRate +
      math.max(
            0,
            grossWages -
                filingStatus.additionalMedicareTaxWagesOver / priceLevel,
          ) *
          _additionalMedicareTaxRate;

  double get _standardDeduction =>
      filingStatus.standardDeduction +
      (filersAreSixtyFiveOrOlder ? filingStatus.extraDeductionAtSixtyFive : 0);

  /// How much more ordinary income [income] can take before its taxable
  /// ordinary income passes the top of the [ratePercent] bracket. Extra
  /// income can make more Social Security taxable, so the room is found by
  /// asking the return, not by subtraction.
  double ordinaryIncomeRoomBelowTopOf(int ratePercent, YearIncome income) {
    final double bracketTop = filingStatus.topOfBracket(ratePercent);
    double overshootAt(double extra) =>
        _taxableIncomeOf(income.plus(ordinaryIncome: extra)).ordinary -
        bracketTop;
    if (overshootAt(0) >= 0) return 0;
    var fits = 0.0;
    var passes = bracketTop + _standardDeduction + 1;
    while (passes - fits > 1) {
      final double middle = (fits + passes) / 2;
      if (overshootAt(middle) <= 0) {
        fits = middle;
      } else {
        passes = middle;
      }
    }
    return fits;
  }

  TaxableIncome _taxableIncomeOf(YearIncome income) {
    final double grossOrdinary =
        income.ordinaryIncome + _taxableSocialSecurityIn(income);
    final double deductionLeftForGains = math.max(
      0,
      _standardDeduction - grossOrdinary,
    );
    return TaxableIncome(
      ordinary: math.max(0, grossOrdinary - _standardDeduction),
      longTermGains: math.max(0, income.longTermGains - deductionLeftForGains),
    );
  }

  /// IRS Pub. 915: up to 50% of benefits over the base amount, up to 85%
  /// over the adjusted base amount, of provisional income.
  double _taxableSocialSecurityIn(YearIncome income) {
    final double benefits = income.socialSecurityBenefits;
    if (benefits <= 0) return 0;
    final double provisionalIncome =
        income.ordinaryIncome + income.longTermGains + benefits / 2;
    final double baseAmount =
        filingStatus.socialSecurityBaseAmount / priceLevel;
    final double adjustedBaseAmount =
        filingStatus.socialSecurityAdjustedBaseAmount / priceLevel;
    if (provisionalIncome <= baseAmount) return 0;
    final double halfTaxedPart = math.min(
      benefits / 2,
      (math.min(provisionalIncome, adjustedBaseAmount) - baseAmount) / 2,
    );
    if (provisionalIncome <= adjustedBaseAmount) return halfTaxedPart;
    return math.min(
      benefits * 0.85,
      0.85 * (provisionalIncome - adjustedBaseAmount) + halfTaxedPart,
    );
  }

  double _ordinaryIncomeTaxOn(double taxableOrdinary) {
    var tax = 0.0;
    var bracketBottom = 0.0;
    for (final bracket in filingStatus.ordinaryBrackets) {
      if (taxableOrdinary <= bracketBottom) break;
      tax +=
          (math.min(taxableOrdinary, bracket.top) - bracketBottom) *
          bracket.ratePercent /
          100;
      bracketBottom = bracket.top;
    }
    return tax;
  }

  /// Gains fill whatever is left of each band above ordinary income.
  double _gainsTaxStackedOn(TaxableIncome taxable) {
    final double gainsBottom = taxable.ordinary;
    final double gainsTop = taxable.ordinary + taxable.longTermGains;
    double gainsBetween(double bandBottom, double bandTop) => math.max(
      0,
      math.min(gainsTop, bandTop) - math.max(gainsBottom, bandBottom),
    );
    return gainsBetween(
              filingStatus.zeroRateGainsTop,
              filingStatus.fifteenRateGainsTop,
            ) *
            _fifteenPercent +
        gainsBetween(filingStatus.fifteenRateGainsTop, double.infinity) *
            _twentyPercent;
  }
}

/// Income left after the standard deduction, split by how it is taxed.
class const TaxableIncome({
  required final double ordinary,
  required final double longTermGains,
});
