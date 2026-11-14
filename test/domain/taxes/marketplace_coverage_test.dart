import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/taxes/federal_income_tax.dart';
import 'package:spend_trends/domain/taxes/filing_status.dart';
import 'package:spend_trends/domain/taxes/marketplace_coverage.dart';

void main() {
  const single = FederalIncomeTax(filingStatus: FilingStatus.single);
  const coverage = MarketplaceCoverage(
    householdSize: 1,
    benchmarkPremiumAnnual: 9000,
  );

  test('the credit is the benchmark less the expected contribution', () {
    // 300% of the poverty line pays 9.96% of income.
    const modifiedAgi = 15650 * 3.0;
    expect(
      coverage.premiumTaxCreditAt(modifiedAgi),
      closeTo(9000 - 0.0996 * modifiedAgi, 0.01),
    );
  });

  test('past 400% of the poverty line the credit is gone', () {
    expect(coverage.premiumTaxCreditAt(15650 * 4.0), greaterThan(0));
    expect(coverage.premiumTaxCreditAt(15650 * 4.0 + 1), 0);
  });

  test('below the poverty line Texas gives no credit', () {
    expect(coverage.premiumTaxCreditAt(15000), 0);
  });

  test('the credit comes back on the return as negative tax', () {
    final IncomeTaxBill bill = single.billFor(
      const YearIncome(ordinaryIncome: 40000, marketplaceCoverage: coverage),
    );
    expect(bill.premiumTaxCredit, greaterThan(0));
    expect(
      bill.total,
      closeTo(
        single.billFor(const YearIncome(ordinaryIncome: 40000)).total -
            bill.premiumTaxCredit,
        0.01,
      ),
    );
  });

  test('conversion room stops at the credit cliff', () {
    expect(
      single.ordinaryIncomeRoomKeepingPremiumTaxCredit(
        const YearIncome(longTermGains: 10000, marketplaceCoverage: coverage),
      ),
      closeTo(15650 * 4 - 10000, 0.01),
    );
    expect(
      single.ordinaryIncomeRoomKeepingPremiumTaxCredit(const YearIncome()),
      double.infinity,
    );
  });

  test('premiums follow the age curve', () {
    expect(
      MarketplacePremiums.adultPremiumAt(64, knownPremium: 1000, knownAge: 21),
      closeTo(3000, 0.01),
    );
    expect(
      MarketplacePremiums.childPremium(knownPremium: 1000, knownAge: 21),
      closeTo(765, 0.01),
    );
  });

  test('taxable wages are what leaves take-home after all payroll tax', () {
    const payrollContributions = 23000.0;
    final double taxableWages = single.taxableWagesBehindTakeHome(
      90000,
      payrollContributions: payrollContributions,
    );
    final double grossWages = taxableWages + payrollContributions;
    final double incomeTax = single
        .billFor(YearIncome(ordinaryIncome: taxableWages))
        .total;
    final double payrollTax = grossWages * (0.062 + 0.0145);
    // Gross stays under the Social Security wage base.
    expect(taxableWages - incomeTax - payrollTax, closeTo(90000, 2));
  });

  test('from 65 the standard deduction grows', () {
    const sixtyFive = FederalIncomeTax(
      filingStatus: FilingStatus.single,
      filersAreSixtyFiveOrOlder: true,
    );
    expect(
      sixtyFive.billFor(const YearIncome(ordinaryIncome: 16100 + 2050)).total,
      0,
    );
  });
}
