import 'dart:math' as math;

import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/accounts/owned_asset.dart';
import 'package:spend_trends/domain/projection/life_plan.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_starting_point.dart';
import 'package:spend_trends/domain/projection/projected_home.dart';
import 'package:spend_trends/domain/projection/projected_savings.dart';
import 'package:spend_trends/domain/projection/savings_balances.dart';
import 'package:spend_trends/domain/projection/year_drawdown.dart';
import 'package:spend_trends/domain/taxes/federal_income_tax.dart';
import 'package:spend_trends/domain/taxes/marketplace_coverage.dart';
import 'package:spend_trends/domain/taxes/retirement_account_rules.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';

/// One simulated year, valued at the end of the year you turn [age], in
/// today's dollars.
class const ProjectionYear({
  required final int age,
  required final int year,
  @override required final double taxable,
  @override required final double traditional,
  @override required final double roth,
  @override required final double college,
  @override required final double homeEquity,

  /// Take-home while working; Social Security (before tax) once retired.
  required final double income,
  required final double spending,

  /// Federal tax and penalties on the year's draws, Roth conversion, and
  /// realized gains, beyond what payroll withheld, less the marketplace
  /// premium tax credit (negative when the credit is larger).
  required final double taxes,

  /// Traditional money moved to Roth this year.
  final double rothConversion = 0,

  /// Mortgage principal and interest plus the home's carrying costs.
  required final double housing,

  /// The principal part of [housing]: it builds home equity, so the three
  /// numbers count it as Investments.
  required final double mortgagePrincipal,

  /// What goes to the mortgage servicer: principal and interest, plus tax
  /// and insurance when the loan has escrow.
  required final double mortgagePayment,

  /// A move's costs this year: selling the old home, carrying it until it
  /// sells, buyer closing costs, and movers (0 without a move).
  final double moveCosts = 0,
}) extends SavingsBalances {
  double get netWorth => liquid + college + homeEquity;
}

/// What a retirement age asks of today's budget: the most you can spend
/// outside housing each year (kept for life) without running out, and the
/// investing that leaves (Three Numbers' Investments: brokerage deposits
/// from take-home, 401(k) payroll contributions, and mortgage principal).
class const RetirementSavingsTarget({
  required final int retirementAge,
  required final double maxNonHousingSpendingAnnual,
  required final double takeHomeAnnual,

  /// Housing including mortgage principal.
  required final double housingAnnual,
  required final double mortgagePrincipalAnnual,
  required final double payrollContributionsAnnual,
}) {
  /// Pay left after spending and housing, with principal counted as
  /// investing rather than housing, as the three numbers count it.
  double get requiredInvestingAnnual =>
      takeHomeAnnual -
      maxNonHousingSpendingAnnual -
      (housingAnnual - mortgagePrincipalAnnual) +
      payrollContributionsAnnual;

  /// Share of pay (take-home plus payroll contributions, the Three Numbers'
  /// denominator), rounded up; 0 when savings already cover the plan.
  int get requiredInvestingPercent {
    final payAnnual = takeHomeAnnual + payrollContributionsAnnual;
    if (payAnnual <= 0) return 0;
    return (math.max(0, requiredInvestingAnnual) / payAnnual * 100).ceil();
  }
}

/// A yearly model started from live data and run in today's dollars (real
/// returns; a fixed-rate mortgage shrinks with inflation).
///
/// Each year: accounts grow; while working, take-home pays spending and
/// housing, payroll contributions go to traditional, and the surplus goes to
/// taxable. A [YearDrawdown] pays any shortfall and the year's federal tax
/// (see it for the order and Roth conversions). Retired, Social Security
/// starts at 62; until Medicare at 65 the household buys the marketplace
/// benchmark plan, and the premium tax credit comes back on the return.
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

  static const _socialSecurityFromAge = 62;
  static const _medicareFromAge = 65;

  /// Part B, Part D, and a Medigap plan, per adult.
  static const _medicareMonthlyPerAdult = 500.0;

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

  /// The simulated year [earliestRetirementAge] falls in; null with it.
  int? get earliestRetirementYear {
    final int? earliest = earliestRetirementAge;
    if (earliest == null) return null;
    return start.today.year + earliest - currentAge!;
  }

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
      mortgagePrincipalAnnual: years.first.mortgagePrincipal,
      payrollContributionsAnnual: start.payrollContributionsAnnual,
    );
  }();

  /// [lifePlan] plus the assumptions' assumed move, if any: the plan the
  /// years run on.
  late final LifePlan lifePlanWithAssumedMove = switch (assumptions.assumedMove(
    currentHome: lifePlan.homeOn(start.today),
  )) {
    null => lifePlan,
    final HomeOwnership assumedHome => lifePlan.withHome(assumedHome),
  };

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

/// One simulation run, a year at a time.
class _YearByYear({
  required final RetirementProjection projection,
  required final int retirementAge,
}) {
  late ProjectedSavings _savings = ProjectedSavings.startingFrom(
    projection.start,
    projection.assumptions,
  );
  late final ProjectedHome _home = ProjectedHome(
    home: projection.lifePlanWithAssumedMove.homeOn(projection.start.today),
    value: projection.start.homeValue,
    mortgageBalanceNominal: projection.start.mortgageBalance,
  );
  late final double _spendingAnnual =
      projection.assumptions.spendingOverrideAnnualDollars?.toDouble() ??
      projection.start.nonHousingSpendingAnnual;
  late final double _realReturn =
      projection.assumptions.realReturnPercent / 100;
  late final double _inflation = projection.assumptions.inflationPercent / 100;
  late final DateTime _penaltyFreeFrom = RetirementAccountRules.penaltyFreeFrom(
    projection.assumptions.birthDate!,
  );
  int _yearsElapsed = 0;

  ProjectionYear advanceTo(int age, {required int year}) {
    _yearsElapsed++;
    final isRetired = age > retirementAge;
    final midYear = DateTime(year, 7, 1);
    final double realizedGains = _savings.growOneYear(
      realReturn: _realReturn,
      inflation: _inflation,
    );
    final HomeMove? move = _home.moveTo(
      projection.lifePlanWithAssumedMove.homeOn(midYear),
      priceLevel: _priceLevel,
    );
    final double takeHome = isRetired
        ? 0
        : projection._takeHomeAnnualOn(midYear);
    final incomeTax = FederalIncomeTax(
      filingStatus: projection.assumptions.filingStatus,
      priceLevel: _priceLevel,
      filersAreSixtyFiveOrOlder: age >= RetirementProjection._medicareFromAge,
    );
    final MarketplaceCoverage? marketplaceCoverage = _marketplaceCoverageAt(
      age,
      year: year,
      isRetired: isRetired,
    );
    final double socialSecurity = _socialSecurityAt(age, isRetired: isRetired);
    if (!isRetired) {
      _savings.traditional += projection.start.payrollContributionsAnnual;
    }
    final double spending =
        _spendingAnnual +
        projection.lifePlanWithAssumedMove.childCostsIn(year) +
        (marketplaceCoverage?.benchmarkPremiumAnnual ?? 0) +
        (age >= RetirementProjection._medicareFromAge ? _medicareAnnual : 0);
    final MortgagePaidInAYear mortgagePaid = _home.payTheMortgageForAYear(
      priceLevel: _priceLevel,
    );
    final double principalAndInterest = mortgagePaid.principalAndInterest;
    final double housing = principalAndInterest + _home.carryingCostAnnual;
    final double paidFromCollege = math.min(
      _savings.college,
      projection.lifePlanWithAssumedMove.collegeCostsIn(year),
    );
    _savings.college -= paidFromCollege;

    final drawdown = YearDrawdown.plan(
      savings: _savings,
      cashNeed:
          spending +
          housing -
          takeHome -
          socialSecurity -
          paidFromCollege -
          (move?.cashFreed ?? 0),
      year: DrawdownYear(
        age: age,
        taxYear: year,
        isPastPenaltyFreeAge: !midYear.isBefore(_penaltyFreeFrom),
        isRetired: isRetired,
      ),
      incomeTax: incomeTax,
      rothConversionBracketPercent:
          projection.assumptions.rothConversionBracketPercent,
      taxableWages: incomeTax.taxableWagesBehindTakeHome(
        takeHome,
        payrollContributions: projection.start.payrollContributionsAnnual,
      ),
      socialSecurityBenefits: socialSecurity,
      realizedGains: realizedGains,
      marketplaceCoverage: marketplaceCoverage,
    );
    _savings = drawdown.savingsAfter;

    return ProjectionYear(
      age: age,
      year: year,
      taxable: _savings.taxable.value,
      traditional: _savings.traditional,
      roth: _savings.roth.balance,
      college: _savings.college,
      homeEquity: _home.equity(priceLevel: _priceLevel),
      income: isRetired ? socialSecurity : takeHome,
      spending: spending,
      taxes: drawdown.taxes,
      rothConversion: drawdown.rothConversion,
      housing: housing,
      mortgagePrincipal: mortgagePaid.principal,
      mortgagePayment:
          principalAndInterest +
          _home.escrowedTaxAndInsurance(principalAndInterest),
      moveCosts: move?.costs ?? 0,
    );
  }

  /// Nominal dollars per today's dollar this year.
  double get _priceLevel => math.pow(1 + _inflation, _yearsElapsed).toDouble();

  double _socialSecurityAt(int age, {required bool isRetired}) {
    if (!isRetired || age < RetirementProjection._socialSecurityFromAge) {
      return 0;
    }
    return projection.assumptions.socialSecurityMonthlyDollars * 12.0;
  }

  double get _medicareAnnual =>
      12 *
      RetirementProjection._medicareMonthlyPerAdult *
      projection.assumptions.filingStatus.adultCount;

  /// Retired before Medicare: the adults (your age) and dependent children
  /// on the benchmark plan.
  MarketplaceCoverage? _marketplaceCoverageAt(
    int age, {
    required int year,
    required bool isRetired,
  }) {
    if (!isRetired || age >= RetirementProjection._medicareFromAge) {
      return null;
    }
    final int adults = projection.assumptions.filingStatus.adultCount;
    final int dependents = projection.lifePlanWithAssumedMove.dependentsIn(
      year,
    );
    final double knownPremium =
        projection.assumptions.marketplacePremiumMonthlyDollars * 12.0;
    final int knownAge = projection.currentAge!;
    return MarketplaceCoverage(
      householdSize: adults + dependents,
      benchmarkPremiumAnnual:
          adults *
              MarketplacePremiums.adultPremiumAt(
                age,
                knownPremium: knownPremium,
                knownAge: knownAge,
              ) +
          dependents *
              MarketplacePremiums.childPremium(
                knownPremium: knownPremium,
                knownAge: knownAge,
              ),
    );
  }
}
