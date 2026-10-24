import 'dart:math' as math;

import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_starting_point.dart';
import 'package:spend_trends/domain/projection/projection_tax_treatment.dart';
import 'package:spend_trends/domain/transaction.dart';

/// One simulated year, valued at the end of the year you turn [age], in
/// today's dollars.
class const ProjectionYear({
  required final int age,
  required final int year,
  required final double taxable,
  required final double traditional,
  required final double roth,
  required final double homeEquity,
  required final double income,
  required final double spending,
  required final double housing,
}) {
  double get liquid => taxable + traditional + roth;

  double get netWorth => liquid + homeEquity;
}

/// What a retirement age asks of today's budget: the most you can spend
/// outside housing each year (kept for life) without running out, and the
/// investing that leaves (Three Numbers' Investments: brokerage deposits
/// from take-home plus 401(k) payroll contributions).
class const RetirementSavingsTarget({
  required final int retirementAge,
  required final double maxNonHousingSpendingAnnual,
  required final double takeHomeAnnual,
  required final double housingAnnual,
  required final double payrollContributionsAnnual,
}) {
  double get requiredInvestingAnnual =>
      takeHomeAnnual -
      maxNonHousingSpendingAnnual -
      housingAnnual +
      payrollContributionsAnnual;

  /// Share of take-home, rounded up; 0 when savings already cover the plan.
  int get requiredInvestingPercent {
    if (takeHomeAnnual <= 0) return 0;
    return (math.max(0, requiredInvestingAnnual) / takeHomeAnnual * 100).ceil();
  }
}

/// budget_for_retirement's yearly model, started from live data and run in
/// today's dollars (real returns; the fixed-rate mortgage shrinks with
/// inflation).
///
/// Each year: accounts grow; while working, take-home pays spending and
/// housing, payroll contributions go to traditional, and the surplus goes to
/// taxable. A shortfall draws taxable first, then traditional, then Roth
/// (penalized before 60), and only then becomes debt. Retired, Social
/// Security starts at 62 and health insurance is self-paid until Medicare.
class RetirementProjection({
  required final ProjectionStartingPoint start,
  required final ProjectionAssumptions assumptions,
}) {
  /// From live accounts, homes, and transactions, as of [today].
  factory fromLiveData({
    required DateTime today,
    required ProjectionAssumptions assumptions,
    required List<Account> accounts,
    required List<OwnedAssetWithValuations> ownedAssets,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
  }) => RetirementProjection(
    assumptions: assumptions,
    start: ProjectionStartingPoint.from(
      today: today,
      accounts: accounts,
      ownedAssets: ownedAssets,
      transactions: transactions,
      categories: categories,
      assumptions: assumptions,
    ),
  );

  static const _earlyWithdrawalBeforeAge = 60;
  static const _socialSecurityFromAge = 62;
  static const _medicareFromAge = 65;
  static const _requiredWithdrawalsFromAge = 75;
  static const _selfPayHealthInsuranceMonthly = 1800.0;
  static const _medicarePremiumMonthly = 500.0;
  static const _longTermCapitalGainsRate = 0.15;

  /// Share of a taxable withdrawal that is gains (conservative).
  static const _taxableGainsShare = 0.9;

  /// Dividends (VTI ~1.6%) plus trades realized each year (~10%), taxed as
  /// long-term gains: the yearly tax drag on taxable holdings.
  static const _taxableRealizedShare = 0.1159;
  static const _earlyWithdrawalPenalty = 0.10;
  static const _debtApr = 0.09;

  /// Age today; null until [ProjectionAssumptions.birthDate] is set.
  int? get currentAge {
    final birthDate = assumptions.birthDate;
    if (birthDate == null) return null;
    final today = start.today;
    final hadBirthdayThisYear =
        today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    return today.year - birthDate.year - (hadBirthdayThisYear ? 0 : 1);
  }

  late final List<ProjectionYear> years = yearsRetiringAt(
    assumptions.retirementAge,
  );

  /// Earliest retirement age whose liquid savings never run out before
  /// [ProjectionAssumptions.endAge]; null if none does (or no birth date).
  late final int? earliestRetirementAge = () {
    final age = currentAge;
    if (age == null) return null;
    for (
      var retirementAge = age;
      retirementAge < assumptions.endAge;
      retirementAge++
    ) {
      final simulated = yearsRetiringAt(retirementAge);
      if (simulated.every((year) => year.liquid >= 0)) return retirementAge;
    }
    return null;
  }();

  /// What retiring at [ProjectionAssumptions.retirementAge] asks of today's
  /// budget; null without a birth date.
  late final RetirementSavingsTarget? savingsTarget = () {
    if (currentAge == null || years.isEmpty) return null;
    final takeHomeAnnual =
        assumptions.takeHomeOverrideAnnualDollars?.toDouble() ??
        start.takeHomeAnnual;
    return RetirementSavingsTarget(
      retirementAge: assumptions.retirementAge,
      maxNonHousingSpendingAnnual: _maxSpendingRetiringOnPlan(takeHomeAnnual),
      takeHomeAnnual: takeHomeAnnual,
      housingAnnual: years.first.housing,
      payrollContributionsAnnual: start.payrollContributionsAnnual,
    );
  }();

  /// Highest yearly non-housing spending (kept for life) that still retires
  /// at the planned age without running out, to the nearest \$100.
  double _maxSpendingRetiringOnPlan(double takeHomeAnnual) {
    bool staysSolvent(double spendingAnnual) => RetirementProjection(
      start: start,
      assumptions: assumptions.merged({
        'spendingOverrideAnnualDollars': spendingAnnual.round(),
      }),
    ).years.every((year) => year.liquid >= 0);

    if (!staysSolvent(0)) return 0;
    var solvent = 0.0;
    var insolvent = math.max(takeHomeAnnual, 100000.0);
    while (staysSolvent(insolvent)) {
      solvent = insolvent;
      insolvent *= 2;
    }
    while (insolvent - solvent > 100) {
      final middle = (solvent + insolvent) / 2;
      if (staysSolvent(middle)) {
        solvent = middle;
      } else {
        insolvent = middle;
      }
    }
    return solvent;
  }

  List<ProjectionYear> yearsRetiringAt(int retirementAge) {
    final age = currentAge;
    if (age == null) return const [];
    final run = _YearByYear(
      start: start,
      assumptions: assumptions,
      retirementAge: retirementAge,
    );
    return [
      for (var yearAge = age + 1; yearAge <= assumptions.endAge; yearAge++)
        run.advanceTo(yearAge, year: start.today.year + (yearAge - age)),
    ];
  }
}

/// Mutable balances for one simulation run.
class _YearByYear({
  required ProjectionStartingPoint start,
  required final ProjectionAssumptions assumptions,
  required final int retirementAge,
}) {
  double taxable = start.balanceFor(ProjectionTaxTreatment.taxable);
  double traditional = start.balanceFor(ProjectionTaxTreatment.traditional);
  double roth = start.balanceFor(ProjectionTaxTreatment.roth);
  double mortgageBalanceNominal = start.mortgageBalance;
  final double homeValue = start.homeValue;
  final double mortgagePaymentAnnualNominal = start.mortgagePaymentMonthly * 12;
  final double takeHomeAnnual =
      assumptions.takeHomeOverrideAnnualDollars?.toDouble() ??
      start.takeHomeAnnual;
  final double spendingAnnual =
      assumptions.spendingOverrideAnnualDollars?.toDouble() ??
      start.nonHousingSpendingAnnual;
  final double payrollContributionsAnnual = start.payrollContributionsAnnual;
  late final double _realReturn = assumptions.realReturnPercent / 100;
  late final double _inflation = assumptions.inflationPercent / 100;
  late final double _retirementTax = assumptions.retirementTaxPercent / 100;
  int _yearsElapsed = 0;

  ProjectionYear advanceTo(int age, {required int year}) {
    _yearsElapsed++;
    final isRetired = age > retirementAge;
    _growAccounts();

    final double income = isRetired
        ? _socialSecurityAfterTax(age)
        : takeHomeAnnual;
    if (!isRetired) traditional += payrollContributionsAnnual;
    final double spending =
        spendingAnnual +
        _childCosts(year) +
        (isRetired ? _healthInsurance(age) : 0);
    final double housing = _housingThisYear();

    final surplus = income - spending - housing;
    if (surplus >= 0) {
      taxable += surplus;
    } else {
      _cover(-surplus, age: age);
    }
    _takeRequiredWithdrawals(age);

    return ProjectionYear(
      age: age,
      year: year,
      taxable: taxable,
      traditional: traditional,
      roth: roth,
      homeEquity: homeValue - mortgageBalanceNominal / _priceLevel,
      income: income,
      spending: spending,
      housing: housing,
    );
  }

  double get _priceLevel => math.pow(1 + _inflation, _yearsElapsed).toDouble();

  void _growAccounts() {
    traditional += traditional * _realReturn;
    roth += roth * _realReturn;
    if (taxable < 0) {
      taxable += taxable * RetirementProjection._debtApr;
      return;
    }
    taxable += taxable * _realReturn;
    taxable -=
        taxable *
        RetirementProjection._taxableRealizedShare *
        RetirementProjection._longTermCapitalGainsRate;
  }

  double _socialSecurityAfterTax(int age) {
    if (age < RetirementProjection._socialSecurityFromAge) return 0;
    final annual = assumptions.socialSecurityMonthlyDollars * 12.0;
    return annual - annual * 0.85 * _retirementTax;
  }

  double _healthInsurance(int age) =>
      12 *
      (age >= RetirementProjection._medicareFromAge
          ? RetirementProjection._medicarePremiumMonthly
          : RetirementProjection._selfPayHealthInsuranceMonthly);

  /// The fixed nominal payment (incl. escrow) until payoff, then the
  /// after-payoff ownership costs, in today's dollars.
  double _housingThisYear() {
    if (mortgageBalanceNominal <= 0) {
      return assumptions.housingAfterPayoffMonthlyDollars * 12.0;
    }
    final interest =
        mortgageBalanceNominal * assumptions.mortgageRatePercent / 100;
    final paid = math.min(
      mortgagePaymentAnnualNominal,
      mortgageBalanceNominal + interest,
    );
    mortgageBalanceNominal += interest - paid;
    return paid / _priceLevel;
  }

  /// Per-child yearly cost by age (budget_for_retirement's estimates).
  double _childCosts(int year) {
    var total = 0.0;
    for (final birthYear in assumptions.childBirthYears) {
      final childAge = year - birthYear;
      if (childAge < 0) continue;
      total += childAge <= 5
          ? 40e3
          : childAge <= 18
          ? 30e3
          : childAge <= 22
          ? 20e3
          : childAge <= 26
          ? 5e3
          : 1e3;
    }
    return total;
  }

  /// Pays [shortfall] from taxable, then traditional, then Roth (penalized
  /// before 60); whatever is left becomes debt (negative taxable).
  void _cover(double shortfall, {required int age}) {
    final isEarly = age < RetirementProjection._earlyWithdrawalBeforeAge;
    var stillNeeded = shortfall;
    if (taxable > 0) {
      const keepRate =
          1 -
          RetirementProjection._taxableGainsShare *
              RetirementProjection._longTermCapitalGainsRate;
      final fromTaxable = math.min(stillNeeded, taxable * keepRate);
      taxable -= fromTaxable / keepRate;
      stillNeeded -= fromTaxable;
    }
    final penalty = isEarly ? RetirementProjection._earlyWithdrawalPenalty : 0;
    final traditionalKeepRate = 1 - _retirementTax - penalty;
    if (stillNeeded > 0 && traditional > 0) {
      final fromTraditional = math.min(
        stillNeeded,
        traditional * traditionalKeepRate,
      );
      traditional -= fromTraditional / traditionalKeepRate;
      stillNeeded -= fromTraditional;
    }
    // Early Roth withdrawals: about half is earnings, taxed and penalized.
    final rothKeepRate = isEarly ? 1 - 0.5 * (_retirementTax + penalty) : 1.0;
    if (stillNeeded > 0 && roth > 0) {
      final fromRoth = math.min(stillNeeded, roth * rothKeepRate);
      roth -= fromRoth / rothKeepRate;
      stillNeeded -= fromRoth;
    }
    taxable -= stillNeeded;
  }

  /// From 75, a share of traditional moves (after tax) to taxable.
  void _takeRequiredWithdrawals(int age) {
    if (age < RetirementProjection._requiredWithdrawalsFromAge ||
        traditional <= 0) {
      return;
    }
    final withdrawal = traditional / (100 - age + 10);
    traditional -= withdrawal;
    taxable += withdrawal * (1 - _retirementTax);
  }
}
