import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/cash_flow_breakdown.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';

void main() {
  Account account(String id, AccountKind kind) => Account(
    id: id,
    externalId: id,
    name: id,
    currency: 'USD',
    balanceCents: 0,
    status: AccountStatus.ok,
    kind: kind,
  );

  final cashFlowBreakdown = CashFlowBreakdown(
    categories: const [
      SpendCategory(
        id: 'cat_dining',
        name: 'Dining',
        sortOrder: 0,
        archived: false,
        consciousSpendingArea: ConsciousSpendingArea.guiltFree,
      ),
    ],
    accounts: [
      account('checking', AccountKind.checking),
      account('brokerage', AccountKind.investment),
      account('hysa', AccountKind.savings),
      account('mortgage', AccountKind.loans),
    ],
  );

  CashFlowContribution contributionOf({
    required String accountId,
    required int amountCents,
    String? categoryId,
  }) => cashFlowBreakdown.contributionOf(
    BankTransaction(
      id: 't',
      accountId: accountId,
      externalId: 't',
      postedAt: DateTime(2026, 1, 1),
      amountCents: amountCents,
      rawDescription: 'x',
      normalizedMerchant: 'X',
      pending: false,
      categoryId: categoryId,
    ),
  );

  test('paychecks on cash accounts are take-home pay', () {
    final paycheck = contributionOf(
      accountId: 'checking',
      amountCents: 436500,
      categoryId: SpecialCategory.income.id,
    );
    expect(paycheck.takeHomeCents, 436500);
    expect(paycheck.spendingCents, 0);
  });

  test('income inside an investment account is a return, not pay', () {
    final dividend = contributionOf(
      accountId: 'brokerage',
      amountCents: 8700,
      categoryId: SpecialCategory.income.id,
    );
    expect(dividend.takeHomeCents, 0);
  });

  test('refunds net against their category and area', () {
    final refund = contributionOf(
      accountId: 'checking',
      amountCents: 2500,
      categoryId: 'cat_dining',
    );
    expect(refund.takeHomeCents, 0);
    expect(refund.spendingCents, -2500);
    expect(refund.area, ConsciousSpendingArea.guiltFree);
    expect(refund.areaCents, -2500);
  });

  test('loan-account payment records and disbursements count nowhere', () {
    final loanPayment = contributionOf(
      accountId: 'mortgage',
      amountCents: 329702,
      categoryId: SpecialCategory.housing.id,
    );
    expect(loanPayment, same(CashFlowContribution.none));

    final escrowDisbursement = contributionOf(
      accountId: 'mortgage',
      amountCents: -576863,
    );
    expect(escrowDisbursement, same(CashFlowContribution.none));
  });

  test('investments count net money put in; transfers count nowhere', () {
    final brokerageDeposit = contributionOf(
      accountId: 'checking',
      amountCents: -100000,
      categoryId: SpecialCategory.investments.id,
    );
    expect(brokerageDeposit.area, ConsciousSpendingArea.investments);
    expect(brokerageDeposit.areaCents, 100000);

    final marginDrawBack = contributionOf(
      accountId: 'checking',
      amountCents: 40000,
      categoryId: SpecialCategory.investments.id,
    );
    expect(marginDrawBack.areaCents, -40000);

    final rsuProceeds = contributionOf(
      accountId: 'checking',
      amountCents: 40000,
      categoryId: SpecialCategory.transfer.id,
    );
    expect(rsuProceeds.area, isNull);

    final brokerageSideOfDeposit = contributionOf(
      accountId: 'brokerage',
      amountCents: 100000,
      categoryId: SpecialCategory.transfer.id,
    );
    expect(brokerageSideOfDeposit.area, isNull);
    expect(brokerageSideOfDeposit.transferCents, 100000);

    final savingsDeposit = contributionOf(
      accountId: 'hysa',
      amountCents: 50000,
      categoryId: SpecialCategory.transfer.id,
    );
    expect(savingsDeposit.area, isNull);

    final cardPayment = contributionOf(
      accountId: 'checking',
      amountCents: -50000,
      categoryId: SpecialCategory.transfer.id,
    );
    expect(cardPayment.area, isNull);
    expect(cardPayment.takeHomeCents, 0);
  });

  test('401(k) contributions fill investments, not take-home pay', () {
    final contribution = contributionOf(
      accountId: 'brokerage',
      amountCents: 84800,
      categoryId: SpecialCategory.investments.id,
    );
    expect(contribution.takeHomeCents, 0);
    expect(contribution.area, ConsciousSpendingArea.investments);
    expect(contribution.areaCents, 84800);
  });

  test('asset sales count nowhere', () {
    final sale = contributionOf(
      accountId: 'mortgage',
      amountCents: 36162500,
      categoryId: SpecialCategory.assetSale.id,
    );
    expect(sale, same(CashFlowContribution.none));
  });
}
