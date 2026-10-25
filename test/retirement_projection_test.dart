import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/projection/life_plan.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_starting_point.dart';
import 'package:spend_trends/domain/account_tax_treatment.dart';
import 'package:spend_trends/domain/projection/assumption_sweep.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';

void main() {
  ProjectionStartingPoint startingPoint({
    double taxable = 500000,
    double traditional = 200000,
    double roth = 300000,
    double college = 0,
    double homeValue = 600000,
    double mortgageBalance = 0,
    double takeHomeAnnual = 150000,
    double nonHousingSpendingAnnual = 60000,
  }) => ProjectionStartingPoint(
    today: DateTime(2026, 10, 24),
    balanceByTreatment: {
      AccountTaxTreatment.taxable: taxable,
      AccountTaxTreatment.traditional: traditional,
      AccountTaxTreatment.roth: roth,
      AccountTaxTreatment.college: college,
      AccountTaxTreatment.excluded: 0,
    },
    treatmentByAccountId: const {},
    homeValue: homeValue,
    mortgageBalance: mortgageBalance,
    takeHomeAnnual: takeHomeAnnual,
    nonHousingSpendingAnnual: nonHousingSpendingAnnual,
    payrollContributionsAnnual: 20000,
  );

  HomeOwnership home({
    String id = 'home',
    required DateTime startedOn,
    int price = 600000,
    int downPayment = 120000,
    Mortgage? mortgage = const Mortgage(
      ratePercent: 6,
      years: 30,
      hasEscrow: false,
    ),
  }) => HomeOwnership(
    id: id,
    title: id,
    startedOn: startedOn,
    price: price,
    downPayment: downPayment,
    mortgage: mortgage,
    insuranceAnnual: 3000,
    hoaAnnual: 1200,
    maintenancePercent: 2,
    propertyTaxPercent: 2,
  );

  RetirementProjection projectionWith({
    ProjectionStartingPoint? start,
    ProjectionAssumptions? assumptions,
    List<LifeEvent> lifeEvents = const [],
  }) => RetirementProjection(
    start: start ?? startingPoint(),
    assumptions:
        assumptions ??
        ProjectionAssumptions(
          birthDate: DateTime(1990),
          retirementAge: 60,
          realReturnPercent: 0,
          inflationPercent: 0,
        ),
    lifePlan: LifePlan(lifeEvents),
  );

  test('no birth date means no projection', () {
    final projection = RetirementProjection(
      lifePlan: LifePlan(const []),
      start: startingPoint(),
      assumptions: const ProjectionAssumptions(),
    );
    expect(projection.currentAge, isNull);
    expect(projection.years, isEmpty);
    expect(projection.earliestRetirementAge, isNull);
  });

  test('runs from next birthday to the end age', () {
    final projection = RetirementProjection(
      lifePlan: LifePlan(const []),
      start: startingPoint(),
      assumptions: ProjectionAssumptions(birthDate: DateTime(1990), endAge: 95),
    );
    expect(projection.currentAge, 36);
    expect(projection.years.first.age, 37);
    expect(projection.years.first.year, 2027);
    expect(projection.years.last.age, 95);
  });

  test('working years add the surplus and payroll contributions', () {
    final firstYear = projectionWith(
      assumptions: ProjectionAssumptions(
        birthDate: DateTime(1990),
        retirementAge: 60,
        realReturnPercent: 0,
      ),
    ).years.first;
    expect(firstYear.traditional, 220000);
    expect(firstYear.income, 150000);
    // No home event: no housing is modeled.
    expect(firstYear.housing, 0);
    // Taxable pays its yearly drag: 11.59% realized, taxed at 15%.
    const taxDrag = 500000 * 0.1159 * 0.15;
    expect(firstYear.taxable, closeTo(500000 - taxDrag + 150000 - 60000, 1));
  });

  test('a job event replaces live take-home from the year it applies', () {
    final years = projectionWith(
      lifeEvents: [
        Job(
          id: 'raise',
          title: 'New job',
          startedOn: DateTime(2028, 3, 1),
          endedOn: DateTime(2028, 3, 1),
          takeHomeSalaryAnnual: 160000,
          takeHomeBonusAnnual: 20000,
        ),
      ],
    ).years;
    expect(years[0].income, 150000);
    expect(years[1].income, 180000);
    expect(years.last.age, 95);
    expect(years.firstWhere((year) => year.age == 59).income, 180000);
  });

  test('the current home is paid down at its terms, then carrying costs '
      'remain', () {
    final years = projectionWith(
      start: startingPoint(mortgageBalance: 100000),
      lifeEvents: [home(startedOn: DateTime(2020), downPayment: 500000)],
    ).years;
    final principalAndInterest = const Mortgage(
      ratePercent: 6,
      years: 30,
      hasEscrow: false,
    ).principalAndInterestAnnual(100000);
    const carryingCosts = 600000 * 0.02 + 3000 + 1200 + 600000 * 0.02;
    expect(
      years.first.housing,
      closeTo(principalAndInterest + carryingCosts, 1),
    );
    expect(years.first.mortgagePayment, closeTo(principalAndInterest, 1));
    expect(years.last.housing, closeTo(carryingCosts, 1));
    expect(years.last.homeEquity, 600000);
  });

  test('escrow adds tax and insurance to the mortgage payment only', () {
    ProjectionYear firstYear({required bool hasEscrow}) => projectionWith(
      start: startingPoint(mortgageBalance: 400000),
      lifeEvents: [
        home(
          startedOn: DateTime(2025),
          mortgage: Mortgage(ratePercent: 6, years: 30, hasEscrow: hasEscrow),
        ),
      ],
    ).years.first;
    final withEscrow = firstYear(hasEscrow: true);
    final withoutEscrow = firstYear(hasEscrow: false);
    expect(withEscrow.housing, withoutEscrow.housing);
    expect(
      withEscrow.mortgagePayment - withoutEscrow.mortgagePayment,
      closeTo(600000 * 0.02 + 3000, 1),
    );
  });

  test('a planned home sells the current one and finances the new one', () {
    final years = projectionWith(
      start: startingPoint(homeValue: 500000, mortgageBalance: 300000),
      lifeEvents: [
        home(id: 'now', startedOn: DateTime(2020), price: 500000),
        home(id: 'next', startedOn: DateTime(2028, 5, 1), price: 900000),
      ],
    ).years;
    final beforeMove = years[0];
    final moveYear = years[1];
    expect(beforeMove.homeEquity, closeTo(500000 - 300000, 15000));
    expect(moveYear.homeEquity, closeTo(120000, 20000));
    const saleProceeds = 500000 * 0.94;
    expect(
      moveYear.taxable - beforeMove.taxable,
      lessThan(saleProceeds - 120000),
    );
    expect(moveYear.housing, greaterThan(beforeMove.housing));
  });

  test('each child adds its yearly cost from its birth year', () {
    final years = projectionWith(
      lifeEvents: [
        ChildBirth(
          id: 'kid',
          title: 'Kid',
          startedOn: DateTime(2028, 7, 1),
          endedOn: DateTime(2028, 7, 1),
        ),
      ],
    ).years;
    expect(years[0].spending, 60000);
    expect(years[1].spending, 82000);
  });

  test('529 money pays college years and stays out of liquid', () {
    RetirementProjection projectionWithCollege(double college) =>
        RetirementProjection(
          lifePlan: LifePlan([
            ChildBirth(
              id: 'kid',
              title: 'Kid',
              startedOn: DateTime(2008, 7, 1),
              endedOn: DateTime(2008, 7, 1),
            ),
          ]),
          start: startingPoint(college: college),
          assumptions: ProjectionAssumptions(
            birthDate: DateTime(1990),
            realReturnPercent: 0,
          ),
        );
    final withoutCollege = projectionWithCollege(0).years;
    final withCollege = projectionWithCollege(100000).years;

    expect(withCollege[0].college, 70000);
    expect(withCollege[0].liquid, withoutCollege[0].liquid + 30000);
    expect(withCollege[3].college, 0);
    expect(withCollege[3].liquid, greaterThan(withoutCollege[3].liquid));
  });

  test('a higher real return never asks you to invest more', () {
    final sweep = AssumptionSweep(
      projection: RetirementProjection(
        lifePlan: LifePlan(const []),
        start: startingPoint(),
        assumptions: ProjectionAssumptions(birthDate: DateTime(1990)),
      ),
      assumptionKey: 'realReturnPercent',
      min: 2,
      max: 9,
      step: 0.1,
      outcomeKind: SweepOutcomeKind.investingPercentNeeded,
    );
    final investingPercents = [
      for (final point in sweep.points) point.outcome!,
    ];
    expect(sweep.points.first.value, 2);
    expect(sweep.points.last.value, 9);
    for (var index = 1; index < investingPercents.length; index++) {
      expect(
        investingPercents[index],
        lessThanOrEqualTo(investingPercents[index - 1]),
      );
    }
  });

  test('retiring earlier never ends richer, and the search finds the edge', () {
    final projection = RetirementProjection(
      lifePlan: LifePlan(const []),
      start: startingPoint(),
      assumptions: ProjectionAssumptions(birthDate: DateTime(1990)),
    );
    final earliest = projection.earliestRetirementAge!;
    expect(
      projection.yearsRetiringAt(earliest).every((year) => year.liquid >= 0),
      isTrue,
    );
    if (earliest > 36) {
      expect(
        projection.yearsRetiringAt(earliest - 1).any((year) => year.liquid < 0),
        isTrue,
      );
    }
    expect(
      projection.yearsRetiringAt(50).last.liquid,
      greaterThan(projection.yearsRetiringAt(45).last.liquid),
    );
  });

  test('tax treatment is inferred from account kind and name', () {
    Account account(String name, AccountKind kind) => Account(
      id: name,
      externalId: name,
      name: name,
      currency: 'USD',
      balanceCents: 0,
      status: AccountStatus.ok,
      kind: kind,
    );
    expect(
      AccountTaxTreatment.inferredFor(
        account('Sunrun Inc. 401(k) Plan', AccountKind.investment),
      ),
      AccountTaxTreatment.traditional,
    );
    expect(
      AccountTaxTreatment.inferredFor(
        account('Roth IRA (6023)', AccountKind.investment),
      ),
      AccountTaxTreatment.roth,
    );
    expect(
      AccountTaxTreatment.inferredFor(
        account('529 Plan (01)', AccountKind.investment),
      ),
      AccountTaxTreatment.college,
    );
    expect(
      AccountTaxTreatment.inferredFor(
        account('M1 Pie', AccountKind.investment),
      ),
      AccountTaxTreatment.taxable,
    );
    expect(
      AccountTaxTreatment.inferredFor(
        account('Alcorn mortgage', AccountKind.loans),
      ),
      AccountTaxTreatment.excluded,
    );
  });

  test(
    'savings target finds the most you can spend and still retire on plan',
    () {
      RetirementProjection retiringAt(int age) => RetirementProjection(
        lifePlan: LifePlan(const []),
        start: startingPoint(taxable: 200000, traditional: 50000, roth: 50000),
        assumptions: ProjectionAssumptions(
          birthDate: DateTime(1990),
          retirementAge: age,
        ),
      );
      final target = retiringAt(50).savingsTarget!;
      expect(target.retirementAge, 50);

      bool solventAt(double spending) => RetirementProjection(
        lifePlan: LifePlan(const []),
        start: startingPoint(taxable: 200000, traditional: 50000, roth: 50000),
        assumptions: ProjectionAssumptions(
          birthDate: DateTime(1990),
          retirementAge: 50,
          spendingOverrideAnnualDollars: spending.round(),
        ),
      ).years.every((year) => year.liquid >= 0);
      expect(solventAt(target.maxNonHousingSpendingAnnual), isTrue);
      expect(solventAt(target.maxNonHousingSpendingAnnual + 500), isFalse);

      expect(
        retiringAt(55).savingsTarget!.requiredInvestingPercent,
        lessThan(target.requiredInvestingPercent),
      );
    },
  );

  test('investments guideline comes from the target once there is one', () {
    final target = RetirementProjection(
      lifePlan: LifePlan(const []),
      start: startingPoint(taxable: 200000, traditional: 50000, roth: 50000),
      assumptions: ProjectionAssumptions(
        birthDate: DateTime(1990),
        retirementAge: 50,
      ),
    ).savingsTarget!;
    final guideline = ConsciousSpendingGuideline.forArea(
      ConsciousSpendingArea.investments,
      retirementTarget: target,
    );
    expect(guideline.rangeLabel, '≥${target.requiredInvestingPercent}%');
    expect(guideline.reason, 'retire at 50');
    expect(guideline.contains(target.requiredInvestingPercent + 30), isTrue);
    expect(
      ConsciousSpendingGuideline.forArea(
        ConsciousSpendingArea.fixedCosts,
        retirementTarget: target,
      ),
      same(ConsciousSpendingArea.fixedCosts.ramitGuideline),
    );
  });

  test('age counts from the birthday, not just the year', () {
    RetirementProjection bornOn(DateTime birthDate) => RetirementProjection(
      lifePlan: LifePlan(const []),
      start: startingPoint(),
      assumptions: ProjectionAssumptions(birthDate: birthDate),
    );
    // Today is 2026-10-24.
    expect(bornOn(DateTime(1990, 11, 22)).currentAge, 35);
    expect(bornOn(DateTime(1990, 10, 24)).currentAge, 36);
  });
}
