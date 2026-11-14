import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/projection/projected_savings.dart';
import 'package:spend_trends/domain/projection/roth_savings.dart';
import 'package:spend_trends/domain/projection/taxable_savings.dart';
import 'package:spend_trends/domain/projection/year_drawdown.dart';
import 'package:spend_trends/domain/taxes/federal_income_tax.dart';
import 'package:spend_trends/domain/taxes/filing_status.dart';
import 'package:spend_trends/domain/taxes/marketplace_coverage.dart';

void main() {
  const single = FederalIncomeTax(filingStatus: FilingStatus.single);
  const retiredAt50 = DrawdownYear(
    age: 50,
    taxYear: 2040,
    isPastPenaltyFreeAge: false,
    isRetired: true,
  );

  ProjectedSavings savingsOf({
    double taxable = 0,
    double taxableCost = 0,
    double traditional = 0,
    double roth = 0,
    double rothContributions = 0,
  }) => ProjectedSavings(
    taxable: TaxableSavings(value: taxable, cost: taxableCost),
    traditional: traditional,
    roth: RothSavings(balance: roth, contributions: rothContributions),
    college: 0,
  );

  group('Roth withdrawal order', () {
    test('contributions, then seasoned conversions, come out free', () {
      final roth = RothSavings(balance: 100000, contributions: 20000)
        ..convertIn(30000, taxYear: 2030);
      expect(
        roth.withdrawableFreely(taxYear: 2034, isPastPenaltyFreeAge: false),
        20000,
      );
      expect(
        roth.withdrawableFreely(taxYear: 2035, isPastPenaltyFreeAge: false),
        50000,
      );
      final RothWithdrawal withdrawal = roth.withdraw(
        60000,
        taxYear: 2035,
        isPastPenaltyFreeAge: false,
      );
      expect(withdrawal.unseasonedConversions, 0);
      expect(withdrawal.earnings, 10000);
    });

    test('everything is free from 59½', () {
      final roth = RothSavings(balance: 100000, contributions: 0);
      expect(
        roth
            .withdraw(100000, taxYear: 2050, isPastPenaltyFreeAge: true)
            .earnings,
        0,
      );
    });
  });

  test('selling taxable realizes only the gain above cost', () {
    final taxable = TaxableSavings(value: 100000, cost: 60000);
    expect(taxable.sell(50000), closeTo(20000, 0.01));
    expect(taxable.cost, closeTo(30000, 0.01));
  });

  test('a surplus is saved to taxable after the tax on realized gains', () {
    final drawdown = YearDrawdown.plan(
      savings: savingsOf(taxable: 100000, taxableCost: 100000),
      cashNeed: -10000,
      year: retiredAt50,
      incomeTax: single,
      rothConversionBracketPercent: null,
      taxableWages: 150000,
      realizedGains: 10000,
    );
    expect(drawdown.taxes, closeTo(1500, 1));
    expect(drawdown.savingsAfter.taxable.value, closeTo(108500, 1));
  });

  test('a shortfall also pays the tax its own sales raise', () {
    final drawdown = YearDrawdown.plan(
      savings: savingsOf(taxable: 1000000, taxableCost: 0),
      cashNeed: 200000,
      year: retiredAt50,
      incomeTax: single,
      rothConversionBracketPercent: null,
    );
    final double sold = 1000000 - drawdown.savingsAfter.taxable.value;
    expect(sold, closeTo(200000 + drawdown.taxes, 1));
    expect(
      drawdown.taxes,
      closeTo(single.billFor(YearIncome(longTermGains: sold)).total, 1),
    );
  });

  test('before 59½, filling a bracket converts and taxable pays the tax', () {
    final drawdown = YearDrawdown.plan(
      savings: savingsOf(
        taxable: 500000,
        taxableCost: 500000,
        traditional: 300000,
      ),
      cashNeed: 60000,
      year: retiredAt50,
      incomeTax: single,
      rothConversionBracketPercent: 12,
    );
    expect(drawdown.rothConversion, closeTo(16100 + 50400, 1));
    expect(
      drawdown.savingsAfter.roth.balance,
      closeTo(drawdown.rothConversion, 0.01),
    );
    expect(drawdown.taxes, closeTo(12400 * 0.10 + (50400 - 12400) * 0.12, 1));
    expect(
      drawdown.savingsAfter.taxable.value,
      closeTo(500000 - 60000 - drawdown.taxes, 1),
    );
  });

  test('filling a bracket stops short of losing the premium credit', () {
    final drawdown = YearDrawdown.plan(
      savings: savingsOf(
        taxable: 500000,
        taxableCost: 500000,
        traditional: 300000,
      ),
      cashNeed: 60000,
      year: retiredAt50,
      incomeTax: single,
      rothConversionBracketPercent: 22,
      marketplaceCoverage: const MarketplaceCoverage(
        householdSize: 1,
        benchmarkPremiumAnnual: 9000,
      ),
    );
    expect(drawdown.rothConversion, closeTo(15650 * 4, 1));
  });

  test('a conversion never forces a penalized withdrawal', () {
    final drawdown = YearDrawdown.plan(
      savings: savingsOf(traditional: 300000),
      cashNeed: 40000,
      year: retiredAt50,
      incomeTax: single,
      rothConversionBracketPercent: 12,
    );
    expect(drawdown.rothConversion, 0);
  });

  test('from 59½ the filled bracket pays spending before converting', () {
    final drawdown = YearDrawdown.plan(
      savings: savingsOf(
        taxable: 500000,
        taxableCost: 500000,
        traditional: 300000,
      ),
      cashNeed: 40000,
      year: const DrawdownYear(
        age: 62,
        taxYear: 2052,
        isPastPenaltyFreeAge: true,
        isRetired: true,
      ),
      incomeTax: single,
      rothConversionBracketPercent: 12,
    );
    final double outflow = 300000 - drawdown.savingsAfter.traditional;
    expect(outflow, closeTo(16100 + 50400, 1));
    expect(
      drawdown.rothConversion,
      closeTo(outflow - 40000 - drawdown.taxes, 1),
    );
  });

  test('required distributions leave traditional and land in taxable', () {
    final drawdown = YearDrawdown.plan(
      savings: savingsOf(traditional: 246000),
      cashNeed: 0,
      year: const DrawdownYear(
        age: 75,
        taxYear: 2065,
        isPastPenaltyFreeAge: true,
        isRetired: true,
      ),
      incomeTax: single,
      rothConversionBracketPercent: null,
    );
    expect(drawdown.savingsAfter.traditional, closeTo(236000, 1));
    expect(drawdown.rothConversion, 0);
    expect(drawdown.savingsAfter.taxable.value, closeTo(10000, 1));
  });
}
