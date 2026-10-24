import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_starting_point.dart';
import 'package:spend_trends/domain/projection/projection_tax_treatment.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';

void main() {
  ProjectionStartingPoint startingPoint({
    double taxable = 500000,
    double traditional = 200000,
    double roth = 300000,
    double mortgageBalance = 0,
    double mortgagePaymentMonthly = 0,
    double takeHomeAnnual = 150000,
    double nonHousingSpendingAnnual = 60000,
  }) => ProjectionStartingPoint(
    today: DateTime(2026, 10, 24),
    balanceByTreatment: {
      ProjectionTaxTreatment.taxable: taxable,
      ProjectionTaxTreatment.traditional: traditional,
      ProjectionTaxTreatment.roth: roth,
      ProjectionTaxTreatment.excluded: 0,
    },
    treatmentByAccountId: const {},
    homeValue: 600000,
    mortgageBalance: mortgageBalance,
    mortgagePaymentMonthly: mortgagePaymentMonthly,
    takeHomeAnnual: takeHomeAnnual,
    nonHousingSpendingAnnual: nonHousingSpendingAnnual,
    payrollContributionsAnnual: 20000,
  );

  test('no birth date means no projection', () {
    final projection = RetirementProjection(
      start: startingPoint(),
      assumptions: const ProjectionAssumptions(),
    );
    expect(projection.currentAge, isNull);
    expect(projection.years, isEmpty);
    expect(projection.earliestRetirementAge, isNull);
  });

  test('runs from next birthday to the end age', () {
    final projection = RetirementProjection(
      start: startingPoint(),
      assumptions: ProjectionAssumptions(birthDate: DateTime(1990), endAge: 95),
    );
    expect(projection.currentAge, 36);
    expect(projection.years.first.age, 37);
    expect(projection.years.first.year, 2027);
    expect(projection.years.last.age, 95);
  });

  test('working years add the surplus and payroll contributions', () {
    final projection = RetirementProjection(
      start: startingPoint(),
      assumptions: ProjectionAssumptions(
        birthDate: DateTime(1990),
        retirementAge: 60,
        realReturnPercent: 0,
      ),
    );
    final firstYear = projection.years.first;
    expect(firstYear.traditional, 220000);
    expect(firstYear.income, 150000);
    // 1,200/mo after-payoff housing with no mortgage.
    expect(firstYear.housing, 14400);
    // Taxable pays its yearly drag: 11.59% realized, taxed at 15%.
    const taxDrag = 500000 * 0.1159 * 0.15;
    expect(
      firstYear.taxable,
      closeTo(500000 - taxDrag + 150000 - 60000 - 14400, 1),
    );
  });

  test('a mortgage is paid until payoff, then ownership costs remain', () {
    final projection = RetirementProjection(
      start: startingPoint(
        mortgageBalance: 100000,
        mortgagePaymentMonthly: 3000,
      ),
      assumptions: ProjectionAssumptions(
        birthDate: DateTime(1990),
        inflationPercent: 0,
        mortgageRatePercent: 6,
      ),
    );
    expect(projection.years.first.housing, 36000);
    final paidOff = projection.years.firstWhere(
      (year) => year.homeEquity == 600000,
    );
    expect(paidOff.age, lessThan(42));
    expect(projection.years.last.housing, 14400);
  });

  test('retiring earlier never ends richer, and the search finds the edge', () {
    final projection = RetirementProjection(
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
      ProjectionTaxTreatment.inferredFor(
        account('Sunrun Inc. 401(k) Plan', AccountKind.investment),
      ),
      ProjectionTaxTreatment.traditional,
    );
    expect(
      ProjectionTaxTreatment.inferredFor(
        account('Roth IRA (6023)', AccountKind.investment),
      ),
      ProjectionTaxTreatment.roth,
    );
    expect(
      ProjectionTaxTreatment.inferredFor(
        account('M1 Pie', AccountKind.investment),
      ),
      ProjectionTaxTreatment.taxable,
    );
    expect(
      ProjectionTaxTreatment.inferredFor(
        account('Alcorn mortgage', AccountKind.loans),
      ),
      ProjectionTaxTreatment.excluded,
    );
  });

  test(
    'savings target finds the most you can spend and still retire on plan',
    () {
      RetirementProjection retiringAt(int age) => RetirementProjection(
        start: startingPoint(taxable: 200000, traditional: 50000, roth: 50000),
        assumptions: ProjectionAssumptions(
          birthDate: DateTime(1990),
          retirementAge: age,
        ),
      );
      final target = retiringAt(50).savingsTarget!;
      expect(target.retirementAge, 50);

      bool solventAt(double spending) => RetirementProjection(
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
      start: startingPoint(),
      assumptions: ProjectionAssumptions(birthDate: birthDate),
    );
    // Today is 2026-10-24.
    expect(bornOn(DateTime(1990, 11, 22)).currentAge, 35);
    expect(bornOn(DateTime(1990, 10, 24)).currentAge, 36);
  });
}
