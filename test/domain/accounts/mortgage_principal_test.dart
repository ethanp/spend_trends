import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_balance_snapshot.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/accounts/mortgage_principal.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';

void main() {
  Account loan(String id) => Account(
    id: id,
    externalId: id,
    name: id,
    currency: 'USD',
    balanceCents: 0,
    status: AccountStatus.ok,
    kind: AccountKind.loans,
  );

  AccountBalanceSnapshot owed(String accountId, CalendarDay day, int cents) =>
      AccountBalanceSnapshot(
        id: '$accountId@$day',
        accountId: accountId,
        balanceCents: cents,
        recordedDay: day,
      );

  final newHome = HomeOwnership(
    id: 'newHome',
    title: 'New home',
    startedOn: DateTime(2026, 1, 7),
    price: 560000,
    downPayment: 28000,
    mortgage: const Mortgage(ratePercent: 5.99, years: 30, hasEscrow: false),
    insuranceAnnual: 4942,
    hoaAnnual: 1555,
    maintenancePercent: 2,
    propertyTaxPercent: 2.1,
  );

  final BankTransaction oldHomePayoff = BankTransaction(
    id: 'payoff',
    accountId: 'oldLoan',
    externalId: 'payoff',
    postedAtMillis: DateTime(2026, 9, 29).millisecondsSinceEpoch,
    amountCents: 36162534,
    rawDescription: 'Payoff, Wire',
    normalizedMerchant: 'PAYOFF',
    pending: false,
    categoryId: SpecialCategory.assetSale.id,
  );

  final mortgagePrincipal = MortgagePrincipal.from(
    through: CalendarDay.of(2026, 10, 31),
    accounts: [loan('oldLoan'), loan('newLoan')],
    transactions: [oldHomePayoff],
    lifeEvents: [newHome],
    balanceSnapshots: [
      owed('oldLoan', CalendarDay.of(2025, 12, 5), -36377886),
      owed('oldLoan', CalendarDay.of(2026, 1, 5), -36333381),
      owed('oldLoan', CalendarDay.of(2026, 2, 5), -36288644),
      owed('oldLoan', CalendarDay.of(2026, 9, 8), -35968895),
      owed('oldLoan', CalendarDay.of(2026, 9, 29), 0),
      owed('oldLoan', CalendarDay.of(2026, 10, 24), -326455),
      owed('oldLoan', CalendarDay.of(2026, 10, 30), 0),
      owed('newLoan', CalendarDay.of(2026, 7, 13), -52877627),
      owed('newLoan', CalendarDay.of(2026, 8, 5), -52822956),
      owed('newLoan', CalendarDay.of(2026, 11, 2), -52712793),
    ],
  );

  List<String> paymentsOn(String month) => [
    for (final payment in mortgagePrincipal.payments)
      if (payment.day.yearMonthKey == month)
        '${payment.day} ${payment.cents}'
            '${payment.isHomeOverlap ? ' overlap' : ''}',
  ];

  test('a loan balance drop is principal, an overlap once a newer home '
      'applies', () {
    expect(paymentsOn('2026-01'), ['2026-01-05 44505']);
    expect(paymentsOn('2026-02'), [
      '2026-02-05 44737 overlap',
      '2026-02-01 53062',
    ]);
    expect(paymentsOn('2026-08'), ['2026-08-05 54671']);
  });

  test('a payoff from a home sale is not principal, and a closed loan pays '
      'none after', () {
    expect(paymentsOn('2026-09'), ['2026-09-08 319749 overlap']);
    expect(paymentsOn('2026-10'), isEmpty);
    expect(paymentsOn('2026-11'), isEmpty);
  });

  test('the home event is amortized until its loan has snapshots', () {
    final List<int> amortizedCents = [
      for (final payment in mortgagePrincipal.payments)
        if (payment.day.day == 1) payment.cents,
    ];
    expect(amortizedCents, [53062, 53327, 53593, 53861, 54130, 54400]);
    expect(
      amortizedCents.fold(0, (sum, cents) => sum + cents),
      newHome.loanAmount * 100 - 52877627,
    );
  });
}
