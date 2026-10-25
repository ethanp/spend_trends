import 'dart:math' as math;

import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/projection/life_plan.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_starting_point.dart';
import 'package:spend_trends/domain/projection/savings_balances.dart';
import 'package:spend_trends/domain/account_tax_treatment.dart';
import 'package:spend_trends/domain/transaction.dart';

/// One simulated year, valued at the end of the year you turn [age], in
/// today's dollars.
class const ProjectionYear({
  required final int age,
  required final int year,
  @override
  required final double taxable,
  @override
  required final double traditional,
  @override
  required final double roth,
  @override
  required final double college,
  @override
  required final double homeEquity,
  required final double income,
  required final double spending,

  /// Mortgage principal and interest plus the home's carrying costs.
  required final double housing,

  /// What goes to the mortgage servicer: principal and interest, plus tax
  /// and insurance when the loan has escrow.
  required final double mortgagePayment,
}) extends SavingsBalances {
  double get netWorth => liquid + college + homeEquity;
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

/// A yearly model started from live data and run in today's dollars (real
/// returns; a fixed-rate mortgage shrinks with inflation).
///
/// Each year: accounts grow; while working, take-home pays spending and
/// housing, payroll contributions go to traditional, and the surplus goes to
/// taxable. A shortfall draws taxable first, then traditional, then Roth
/// (penalized before 60), and only then becomes debt. Retired, Social
/// Security starts at 62 and health insurance is self-paid until Medicare.
///
/// Life events change the plan from the first year they apply at mid-year:
/// a job sets take-home, a home is bought (selling the one before it), and
/// each child adds its yearly cost. College years are paid from 529 money
/// first; what is left there never funds retirement.
class RetirementProjection({
  required final ProjectionStartingPoint start,
  required final ProjectionAssumptions assumptions,
  required final LifePlan lifePlan,
}) {
  /// From live accounts, homes, transactions, and life events, as of [today].
  factory fromLiveData({
    required DateTime today,
    required ProjectionAssumptions assumptions,
    required List<Account> accounts,
    required List<OwnedAssetWithValuations> ownedAssets,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
    required List<LifeEvent> lifeEvents,
  }) => RetirementProjection(
    assumptions: assumptions,
    lifePlan: LifePlan(lifeEvents),
    start: ProjectionStartingPoint.from(
      today: today,
      accounts: accounts,
      ownedAssets: ownedAssets,
      transactions: transactions,
      categories: categories,
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

  /// Agent commission and seller closing costs, as a share of the sale price.
  static const _homeSellingCostShare = 0.06;

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
    final takeHomeAnnual = _takeHomeAnnualOn(start.today);
    return RetirementSavingsTarget(
      retirementAge: assumptions.retirementAge,
      maxNonHousingSpendingAnnual: _maxSpendingRetiringOnPlan(takeHomeAnnual),
      takeHomeAnnual: takeHomeAnnual,
      housingAnnual: years.first.housing,
      payrollContributionsAnnual: start.payrollContributionsAnnual,
    );
  }();

  /// The job event's take-home on [day], or the last 365 days' without one.
  double _takeHomeAnnualOn(DateTime day) =>
      lifePlan.jobOn(day)?.takeHomeAnnual.toDouble() ?? start.takeHomeAnnual;

  /// Highest yearly non-housing spending (kept for life) that still retires
  /// at the planned age without running out, to the nearest \$100.
  double _maxSpendingRetiringOnPlan(double takeHomeAnnual) {
    bool staysSolvent(double spendingAnnual) => RetirementProjection(
      start: start,
      lifePlan: lifePlan,
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
    final run = _YearByYear(projection: this, retirementAge: retirementAge);
    return [
      for (var yearAge = age + 1; yearAge <= assumptions.endAge; yearAge++)
        run.advanceTo(yearAge, year: start.today.year + (yearAge - age)),
    ];
  }
}

/// Mutable balances for one simulation run.
class _YearByYear({
  required final RetirementProjection projection,
  required final int retirementAge,
}) {
  late double taxable = projection.start.balanceFor(
    AccountTaxTreatment.taxable,
  );
  late double traditional = projection.start.balanceFor(
    AccountTaxTreatment.traditional,
  );
  late double roth = projection.start.balanceFor(AccountTaxTreatment.roth);
  late double college = projection.start.balanceFor(
    AccountTaxTreatment.college,
  );
  late HomeOwnership? _home = projection.lifePlan.homeOn(
    projection.start.today,
  );

  /// Today's value of the home you hold (today's dollars).
  late double _homeValue = projection.start.homeValue;
  late double _mortgageBalanceNominal = projection.start.mortgageBalance;
  late double _principalAndInterestAnnualNominal =
      _home?.mortgage?.principalAndInterestAnnual(
        _home!.loanAmount.toDouble(),
      ) ??
      0;
  late final double _spendingAnnual =
      projection.assumptions.spendingOverrideAnnualDollars?.toDouble() ??
      projection.start.nonHousingSpendingAnnual;
  late final double _realReturn =
      projection.assumptions.realReturnPercent / 100;
  late final double _inflation = projection.assumptions.inflationPercent / 100;
  late final double _retirementTax =
      projection.assumptions.retirementTaxPercent / 100;
  int _yearsElapsed = 0;

  ProjectionYear advanceTo(int age, {required int year}) {
    _yearsElapsed++;
    final isRetired = age > retirementAge;
    final midYear = DateTime(year, 7, 1);
    _growAccounts();
    _moveIfTheHomeChanged(midYear);

    final double income = isRetired
        ? _socialSecurityAfterTax(age)
        : projection._takeHomeAnnualOn(midYear);
    if (!isRetired) {
      traditional += projection.start.payrollContributionsAnnual;
    }
    final double spending =
        _spendingAnnual +
        projection.lifePlan.childCostsIn(year) +
        (isRetired ? _healthInsurance(age) : 0);
    final double principalAndInterest = _payTheMortgageForAYear();
    final double housing =
        principalAndInterest + (_home?.carryingCostAnnual(_homeValue) ?? 0);
    final double paidFromCollege = math.min(
      college,
      projection.lifePlan.collegeCostsIn(year),
    );
    college -= paidFromCollege;

    final surplus = income + paidFromCollege - spending - housing;
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
      college: college,
      homeEquity: _homeValue - _mortgageBalanceNominal / _priceLevel,
      income: income,
      spending: spending,
      housing: housing,
      mortgagePayment:
          principalAndInterest + _escrowedTaxAndInsurance(principalAndInterest),
    );
  }

  double get _priceLevel => math.pow(1 + _inflation, _yearsElapsed).toDouble();

  void _growAccounts() {
    traditional += traditional * _realReturn;
    roth += roth * _realReturn;
    college += college * _realReturn;
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
    final annual = projection.assumptions.socialSecurityMonthlyDollars * 12.0;
    return annual - annual * 0.85 * _retirementTax;
  }

  double _healthInsurance(int age) =>
      12 *
      (age >= RetirementProjection._medicareFromAge
          ? RetirementProjection._medicarePremiumMonthly
          : RetirementProjection._selfPayHealthInsuranceMonthly);

  /// When a different home event applies, sells the home you hold (proceeds
  /// after selling costs and the loan go to taxable) and buys the new one
  /// (the cash part of its price comes from taxable).
  void _moveIfTheHomeChanged(DateTime midYear) {
    final HomeOwnership? nextHome = projection.lifePlan.homeOn(midYear);
    if (nextHome?.id == _home?.id) return;
    taxable +=
        _homeValue * (1 - RetirementProjection._homeSellingCostShare) -
        _mortgageBalanceNominal / _priceLevel;
    _home = nextHome;
    _homeValue = (nextHome?.price ?? 0).toDouble();
    _mortgageBalanceNominal = (nextHome?.loanAmount ?? 0) * _priceLevel;
    _principalAndInterestAnnualNominal =
        nextHome?.mortgage?.principalAndInterestAnnual(
          _mortgageBalanceNominal,
        ) ??
        0;
    if (nextHome != null) taxable -= nextHome.price - nextHome.loanAmount;
  }

  /// The fixed nominal principal and interest until payoff, in today's
  /// dollars; 0 without a home event's mortgage terms.
  double _payTheMortgageForAYear() {
    final Mortgage? mortgage = _home?.mortgage;
    if (mortgage == null || _mortgageBalanceNominal <= 0) return 0;
    final interest = _mortgageBalanceNominal * mortgage.ratePercent / 100;
    final paid = math.min(
      _principalAndInterestAnnualNominal,
      _mortgageBalanceNominal + interest,
    );
    _mortgageBalanceNominal += interest - paid;
    return paid / _priceLevel;
  }

  /// Tax and insurance the servicer collects while the loan is being paid.
  double _escrowedTaxAndInsurance(double principalAndInterest) {
    final HomeOwnership? home = _home;
    if (home == null ||
        home.mortgage?.hasEscrow != true ||
        principalAndInterest == 0) {
      return 0;
    }
    return home.propertyTaxAnnual(_homeValue) + home.insuranceAnnual;
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
