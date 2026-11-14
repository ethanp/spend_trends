import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/taxes/federal_income_tax.dart';
import 'package:spend_trends/domain/taxes/filing_status.dart';
import 'package:spend_trends/domain/taxes/retirement_account_rules.dart';

void main() {
  const single = FederalIncomeTax(filingStatus: FilingStatus.single);

  test('ordinary income is taxed bracket by bracket after the deduction', () {
    final IncomeTaxBill bill = single.billFor(
      const YearIncome(ordinaryIncome: 16100 + 60000),
    );
    const expected =
        12400 * 0.10 + (50400 - 12400) * 0.12 + (60000 - 50400) * 0.22;
    expect(bill.ordinaryIncomeTax, closeTo(expected, 0.01));
    expect(bill.capitalGainsTax, 0);
  });

  test('long-term gains stack on ordinary income: 0% until the band ends', () {
    expect(
      single.billFor(const YearIncome(longTermGains: 16100 + 49450)).total,
      0,
    );
    final IncomeTaxBill stacked = single.billFor(
      const YearIncome(ordinaryIncome: 16100 + 40000, longTermGains: 20000),
    );
    expect(stacked.capitalGainsTax, closeTo((60000 - 49450) * 0.15, 0.01));
  });

  test('Social Security is untaxed at low income and at most 85% taxed', () {
    expect(
      single.billFor(const YearIncome(socialSecurityBenefits: 30000)).total,
      0,
    );
    final IncomeTaxBill highIncome = single.billFor(
      const YearIncome(ordinaryIncome: 200000, socialSecurityBenefits: 30000),
    );
    final IncomeTaxBill withoutBenefits = single.billFor(
      const YearIncome(ordinaryIncome: 200000 + 30000 * 0.85),
    );
    expect(highIncome.total, closeTo(withoutBenefits.total, 0.01));
  });

  test('unindexed Social Security thresholds bite harder as prices rise', () {
    const income = YearIncome(
      ordinaryIncome: 20000,
      socialSecurityBenefits: 30000,
    );
    expect(
      const FederalIncomeTax(
        filingStatus: FilingStatus.single,
        priceLevel: 2,
      ).billFor(income).total,
      greaterThan(single.billFor(income).total),
    );
  });

  test('room below a bracket top counts the deduction', () {
    expect(
      single.ordinaryIncomeRoomBelowTopOf(12, const YearIncome()),
      closeTo(16100 + 50400, 1),
    );
    expect(
      const FederalIncomeTax(filingStatus: FilingStatus.marriedFilingJointly)
          .ordinaryIncomeRoomBelowTopOf(12, const YearIncome()),
      closeTo(32200 + 100800, 1),
    );
  });

  test('room shrinks faster than income when it makes benefits taxable', () {
    final double room = single.ordinaryIncomeRoomBelowTopOf(
      12,
      const YearIncome(socialSecurityBenefits: 30000),
    );
    expect(room, lessThan(16100 + 50400 - 1));
    final double taxableOrdinaryAtRoom = single
        .billFor(
          YearIncome(ordinaryIncome: room, socialSecurityBenefits: 30000),
        )
        .ordinaryIncomeTax;
    expect(
      taxableOrdinaryAtRoom,
      closeTo(12400 * 0.10 + (50400 - 12400) * 0.12, 1),
    );
  });

  test('money taken before 59½ pays a 10% penalty', () {
    expect(
      single
          .billFor(const YearIncome(takenBeforePenaltyFreeAge: 20000))
          .earlyWithdrawalPenalty,
      2000,
    );
  });

  test('59½ is counted from the birth date', () {
    expect(
      RetirementAccountRules.penaltyFreeFrom(DateTime(1990, 11, 22)),
      DateTime(2050, 5, 22),
    );
  });

  test('required distributions follow the uniform lifetime table', () {
    expect(RetirementAccountRules.requiredDistributionAt(74, 100000), 0);
    expect(
      RetirementAccountRules.requiredDistributionAt(75, 246000),
      closeTo(10000, 0.01),
    );
    expect(
      RetirementAccountRules.requiredDistributionAt(90, 122000),
      closeTo(10000, 0.01),
    );
  });
}
