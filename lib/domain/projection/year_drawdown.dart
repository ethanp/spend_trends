import 'dart:math' as math;

import 'package:spend_trends/domain/projection/projected_savings.dart';
import 'package:spend_trends/domain/projection/roth_savings.dart';
import 'package:spend_trends/domain/taxes/federal_income_tax.dart';
import 'package:spend_trends/domain/taxes/marketplace_coverage.dart';
import 'package:spend_trends/domain/taxes/retirement_account_rules.dart';

/// Where a projected year stands: whose age, which tax year, and whether
/// 59½ has passed by mid-year.
class const DrawdownYear({
  required final int age,
  required final int taxYear,
  required final bool isPastPenaltyFreeAge,
  required final bool isRetired,
});

/// How one year's cash need is drawn from savings, and the federal tax
/// that drawing adds.
///
/// Withdrawals, conversions, and sales are different moves: a withdrawal
/// pays spending, a Roth conversion moves traditional money to Roth and
/// only adds taxable income, and a taxable sale realizes a gain.
///
/// Order, cheapest tax first given what can be reached:
/// - Retired with a conversion bracket: traditional money first fills
///   ordinary income to the top of that bracket, stopping short of the
///   income that would lose the marketplace premium tax credit. From 59½
///   it pays spending and the rest converts; before, all of it converts. A
///   conversion never forces a penalized withdrawal.
/// - Required distributions leave traditional from 75 whatever else
///   happens; what spending does not use goes to taxable.
/// - Then taxable. From 59½: traditional, then Roth. Before: Roth
///   contributions and seasoned conversions, then traditional (penalized),
///   then the rest of Roth (penalized; earnings taxed).
/// - Whatever is left is debt.
///
/// Taxes are themselves a cash need, and paying them can raise them (and
/// shrink the premium tax credit), so the plan is re-drawn until the taxes
/// it pays are the taxes it owes.
class YearDrawdown._({
  required final ProjectedSavings savingsAfter,

  /// Federal tax and penalties the year's draws, conversion, and realized
  /// gains add (beyond tax already withheld from wages), less the premium
  /// tax credit; negative when the credit is larger.
  required final double taxes,
  required final double rothConversion,
}) {
  /// Draws for [cashNeed] (negative is a surplus, saved to taxable) plus
  /// its taxes from [savings], which is left unchanged.
  ///
  /// [taxableWages] were taxed through payroll: they set the brackets the
  /// year's draws land in, and their own tax is not counted again.
  /// [marketplaceCoverage]'s premium is in [cashNeed]; its credit comes
  /// back through the taxes.
  factory plan({
    required ProjectedSavings savings,
    required double cashNeed,
    required DrawdownYear year,
    required FederalIncomeTax incomeTax,
    required int? rothConversionBracketPercent,
    double taxableWages = 0,
    double socialSecurityBenefits = 0,
    double realizedGains = 0,
    MarketplaceCoverage? marketplaceCoverage,
  }) {
    final incomeBeforeDraws = YearIncome(
      ordinaryIncome: taxableWages,
      longTermGains: realizedGains,
      socialSecurityBenefits: socialSecurityBenefits,
      marketplaceCoverage: marketplaceCoverage,
    );
    final double requiredDistribution =
        RetirementAccountRules.requiredDistributionAt(
          year.age,
          savings.traditional,
        );
    final double bracketFill =
        !year.isRetired || rothConversionBracketPercent == null
        ? 0
        : math.min(
            incomeTax.ordinaryIncomeRoomBelowTopOf(
              rothConversionBracketPercent,
              incomeBeforeDraws,
            ),
            incomeTax.ordinaryIncomeRoomKeepingPremiumTaxCredit(
              incomeBeforeDraws,
            ),
          );
    final drawing = _Drawing(
      savings: savings,
      cashNeed: cashNeed,
      year: year,
      incomeTax: incomeTax,
      incomeBeforeDraws: incomeBeforeDraws,
      taxAlreadyPaid: incomeTax
          .billFor(YearIncome(ordinaryIncome: taxableWages))
          .total,
      requiredDistribution: requiredDistribution,
    );
    final _DrawnYear withFill = drawing.withTaxesCovered(
      traditionalOutflow: math.max(requiredDistribution, bracketFill),
    );
    final _DrawnYear chosen =
        withFill.wasPenalized && withFill.rothConversion > 0
        ? drawing.withTaxesCovered(traditionalOutflow: requiredDistribution)
        : withFill;
    return YearDrawdown._(
      savingsAfter: chosen.savings,
      taxes: chosen.taxes,
      rothConversion: chosen.rothConversion,
    );
  }
}

/// One year's inputs, drawn as often as the taxes take to settle.
class _Drawing({
  required final ProjectedSavings savings,
  required final double cashNeed,
  required final DrawdownYear year,
  required final FederalIncomeTax incomeTax,
  required final YearIncome incomeBeforeDraws,
  required final double taxAlreadyPaid,
  required final double requiredDistribution,
}) {
  static const _maxRounds = 40;
  static const _settledWithinDollars = 1.0;

  _DrawnYear withTaxesCovered({required double traditionalOutflow}) {
    var taxes = 0.0;
    late _DrawnYear drawn;
    for (var round = 0; round < _maxRounds; round++) {
      drawn = _drawOnce(
        traditionalOutflow: traditionalOutflow,
        taxesToPay: taxes,
      );
      if ((drawn.taxes - taxes).abs() < _settledWithinDollars) break;
      taxes = drawn.taxes;
    }
    return drawn;
  }

  _DrawnYear _drawOnce({
    required double traditionalOutflow,
    required double taxesToPay,
  }) {
    final draws = _Draws(savings: savings.copy(), year: year);
    var stillNeeded = cashNeed + taxesToPay;
    stillNeeded = draws.takePlannedTraditional(
      math.min(traditionalOutflow, draws.savings.traditional),
      stillNeeded: stillNeeded,
      requiredDistribution: requiredDistribution,
    );
    if (stillNeeded <= 0) {
      draws.savings.taxable.deposit(-stillNeeded);
    } else {
      draws.coverFromEveryAccount(stillNeeded);
    }
    final IncomeTaxBill bill = incomeTax.billFor(
      incomeBeforeDraws.plus(
        ordinaryIncome: draws.ordinaryIncome,
        longTermGains: draws.longTermGains,
        takenBeforePenaltyFreeAge: draws.penalized,
      ),
    );
    return _DrawnYear(
      savings: draws.savings,
      taxes: bill.total - taxAlreadyPaid,
      rothConversion: draws.rothConversion,
      wasPenalized: draws.penalized > 0,
    );
  }
}

/// One attempt's moves, made on a copy of savings, and the income they
/// put on the return.
class _Draws({
  required final ProjectedSavings savings,
  required final DrawdownYear year,
}) {
  double ordinaryIncome = 0;
  double longTermGains = 0;
  double penalized = 0;
  double rothConversion = 0;

  /// Takes [outflow] from traditional: spent first from 59½, the required
  /// part left over saved to taxable, the rest converted. Returns the need
  /// still uncovered.
  double takePlannedTraditional(
    double outflow, {
    required double stillNeeded,
    required double requiredDistribution,
  }) {
    if (outflow <= 0) return stillNeeded;
    savings.traditional -= outflow;
    ordinaryIncome += outflow;
    final double spent = year.isPastPenaltyFreeAge
        ? math.min(outflow, math.max(0, stillNeeded))
        : 0;
    final double requiredLeftOver = math.max(0, requiredDistribution - spent);
    savings.taxable.deposit(requiredLeftOver);
    rothConversion = outflow - spent - requiredLeftOver;
    savings.roth.convertIn(rothConversion, taxYear: year.taxYear);
    return stillNeeded - spent;
  }

  void coverFromEveryAccount(double need) {
    var stillNeeded = _sellTaxable(need);
    if (year.isPastPenaltyFreeAge) {
      stillNeeded = _takeTraditional(stillNeeded);
      stillNeeded = _takeRoth(stillNeeded, upTo: savings.roth.balance);
    } else {
      stillNeeded = _takeRoth(
        stillNeeded,
        upTo: savings.roth.withdrawableFreely(
          taxYear: year.taxYear,
          isPastPenaltyFreeAge: false,
        ),
      );
      stillNeeded = _takeTraditional(stillNeeded);
      stillNeeded = _takeRoth(stillNeeded, upTo: savings.roth.balance);
    }
    if (stillNeeded > 0) savings.taxable.borrow(stillNeeded);
  }

  double _sellTaxable(double need) {
    final double sold = math.min(need, math.max(0, savings.taxable.value));
    longTermGains += savings.taxable.sell(sold);
    return need - sold;
  }

  double _takeTraditional(double need) {
    final double taken = math.min(need, math.max(0, savings.traditional));
    savings.traditional -= taken;
    ordinaryIncome += taken;
    if (!year.isPastPenaltyFreeAge) penalized += taken;
    return need - taken;
  }

  double _takeRoth(double need, {required double upTo}) {
    final double taken = math.min(need, math.max(0, upTo));
    if (taken <= 0) return need;
    final RothWithdrawal withdrawal = savings.roth.withdraw(
      taken,
      taxYear: year.taxYear,
      isPastPenaltyFreeAge: year.isPastPenaltyFreeAge,
    );
    ordinaryIncome += withdrawal.earnings;
    penalized += withdrawal.earnings + withdrawal.unseasonedConversions;
    return need - taken;
  }
}

class const _DrawnYear({
  required final ProjectedSavings savings,
  required final double taxes,
  required final double rothConversion,
  required final bool wasPenalized,
});
