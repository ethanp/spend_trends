import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers.dart';

void main() {
  BankTransaction transaction(
    String id,
    DateTime postedAt,
    int cents,
    String categoryId, {
    String accountId = 'checking',
    bool excludedFromLifestyleCosts = false,
  }) => BankTransaction(
    id: id,
    accountId: accountId,
    externalId: id,
    postedAtMillis: postedAt.millisecondsSinceEpoch,
    amountCents: cents,
    rawDescription: id,
    normalizedMerchant: id,
    pending: false,
    categoryId: categoryId,
    excludedFromLifestyleCosts: excludedFromLifestyleCosts,
  );

  test('each window is a plain total over its days ending today', () {
    final today = DateTime(2026, 10, 24);
    final numbers = ConsciousSpendingNumbers.endingOn(
      today: today,
      balanceSnapshots: const [],
      lifeEvents: const [],
      accounts: const [
        Account(
          id: 'k401',
          externalId: 'k401',
          name: '401(k)',
          currency: 'USD',
          balanceCents: 0,
          status: AccountStatus.ok,
          kind: AccountKind.investment,
        ),
      ],
      categories: const [
        SpendCategory(
          id: 'cat_dining',
          name: 'Dining',
          sortOrder: 0,
          archived: false,
          consciousSpendingArea: ConsciousSpendingArea.guiltFree,
        ),
      ],
      transactions: [
        transaction(
          'pay',
          DateTime(2026, 6, 1),
          100000,
          SpecialCategory.income.id,
        ),
        transaction(
          'oldPay',
          DateTime(2025, 6, 1),
          100000,
          SpecialCategory.income.id,
        ),
        transaction(
          'payroll401k',
          DateTime(2026, 7, 1),
          25000,
          SpecialCategory.investments.id,
          accountId: 'k401',
        ),
        transaction('yearStart', DateTime(2025, 10, 25), -10000, 'cat_dining'),
        transaction(
          'justOutsideYear',
          DateTime(2025, 10, 24),
          -50000,
          'cat_dining',
        ),
        transaction('today', DateTime(2026, 10, 24, 18), -15000, 'cat_dining'),
        transaction(
          'movingDinner',
          DateTime(2026, 9, 1),
          -5000,
          'cat_dining',
          excludedFromLifestyleCosts: true,
        ),
        transaction('tomorrow', DateTime(2026, 10, 25), -99999, 'cat_dining'),
      ],
    );

    final lastYear = numbers.totalsFor(ConsciousSpendingWindow.oneYear);
    expect(lastYear.firstDay, DateTime(2025, 10, 25));
    expect(lastYear.takeHomeCents, 100000);
    expect(lastYear.payrollContributionCents, 25000);
    expect(lastYear.payCents, 125000);
    expect(lastYear.centsByArea[ConsciousSpendingArea.guiltFree], 25000);
    expect(lastYear.percentOfPay(ConsciousSpendingArea.guiltFree), 20);
    expect(lastYear.centsByArea[ConsciousSpendingArea.investments], 25000);
    expect(lastYear.percentOfPay(ConsciousSpendingArea.investments), 20);
    expect(lastYear.excludedFromLifestyleCents, 5000);
    expect(lastYear.excludedFromLifestylePercentOfPay, 4);
    expect(lastYear.savingsCents, 70000);
    expect(lastYear.savingsPercentOfPay, 56);

    final lastTwoYears = numbers.totalsFor(ConsciousSpendingWindow.twoYears);
    expect(lastTwoYears.takeHomeCents, 200000);
    expect(lastTwoYears.payCents, 225000);
    expect(lastTwoYears.centsByArea[ConsciousSpendingArea.guiltFree], 75000);
    expect(lastTwoYears.annualCents(ConsciousSpendingArea.guiltFree), 37500);

    final lastSixMonths = numbers.totalsFor(ConsciousSpendingWindow.sixMonths);
    expect(lastSixMonths.firstDay, DateTime(2026, 4, 25));
    expect(lastSixMonths.centsByArea[ConsciousSpendingArea.guiltFree], 15000);
  });

  test('mortgage principal moves from Fixed costs, or from excluded spending '
      'during a home overlap, to Investments; savings stays put', () {
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
    ConsciousSpendingWindowTotals lastSixMonths({
      required List<AccountBalanceSnapshot> balanceSnapshots,
      required List<LifeEvent> lifeEvents,
    }) => ConsciousSpendingNumbers.endingOn(
      today: DateTime(2026, 10, 31),
      accounts: [loan('oldLoan'), loan('newLoan')],
      categories: [SpecialCategory.housing.asSpendCategory()],
      balanceSnapshots: balanceSnapshots,
      lifeEvents: lifeEvents,
      transactions: [
        transaction(
          'pay',
          DateTime(2026, 8, 1),
          1000000,
          SpecialCategory.income.id,
        ),
        transaction(
          'newHomeMortgage',
          DateTime(2026, 8, 3),
          -329702,
          SpecialCategory.housing.id,
        ),
        transaction(
          'oldHomeMortgage',
          DateTime(2026, 8, 5),
          -326455,
          SpecialCategory.housing.id,
          excludedFromLifestyleCosts: true,
        ),
      ],
    ).totalsFor(ConsciousSpendingWindow.sixMonths);

    final withoutPrincipal = lastSixMonths(
      balanceSnapshots: const [],
      lifeEvents: const [],
    );
    final withPrincipal = lastSixMonths(
      balanceSnapshots: [
        owed('oldLoan', CalendarDay.of(2025, 12, 5), -36061441),
        owed('oldLoan', CalendarDay.of(2026, 8, 5), -36015288),
        owed('newLoan', CalendarDay.of(2026, 7, 13), -52877627),
        owed('newLoan', CalendarDay.of(2026, 8, 5), -52822956),
      ],
      lifeEvents: [
        HomeOwnership(
          id: 'newHome',
          title: 'New home',
          startedOn: DateTime(2026, 1, 7),
          price: 560000,
          downPayment: 28000,
          mortgage: const Mortgage(
            ratePercent: 5.99,
            years: 30,
            hasEscrow: false,
          ),
          insuranceAnnual: 4942,
          hoaAnnual: 1555,
          maintenancePercent: 2,
          propertyTaxPercent: 2.1,
        ),
      ],
    );

    const amortizedJuneAndJulyCents = 54130 + 54400;
    const newHomeAugustCents = 54671;
    const oldHomeAugustCents = 46153;
    expect(
      withPrincipal.mortgagePrincipalCents,
      amortizedJuneAndJulyCents + newHomeAugustCents + oldHomeAugustCents,
    );
    expect(
      withPrincipal.centsByArea[ConsciousSpendingArea.investments],
      withPrincipal.mortgagePrincipalCents,
    );
    expect(
      withPrincipal.centsByArea[ConsciousSpendingArea.fixedCosts],
      329702 - amortizedJuneAndJulyCents - newHomeAugustCents,
    );
    expect(
      withPrincipal.excludedFromLifestyleCents,
      326455 - oldHomeAugustCents,
    );
    expect(withPrincipal.savingsCents, withoutPrincipal.savingsCents);
    expect(withoutPrincipal.mortgagePrincipalCents, 0);
  });

  test(
    'guideline score: 0 on target, toward 1 when beaten, -1 when missed',
    () {
      expect(ConsciousSpendingArea.fixedCosts.ramitGuideline.score(55), 0);
      expect(ConsciousSpendingArea.fixedCosts.ramitGuideline.score(45), 0.5);
      expect(ConsciousSpendingArea.fixedCosts.ramitGuideline.score(82), -1);
      expect(ConsciousSpendingArea.investments.ramitGuideline.score(44), 1);
      expect(ConsciousSpendingArea.investments.ramitGuideline.score(4), -0.3);
      expect(ConsciousSpendingArea.guiltFree.ramitGuideline.score(24), 0.3);
    },
  );

  test('savings misses its 0% target in either direction', () {
    expect(ConsciousSpendingGuideline.savings.isMetBy(0), isTrue);
    expect(ConsciousSpendingGuideline.savings.score(10), -0.5);
    expect(ConsciousSpendingGuideline.savings.score(-14), -0.7);
    expect(ConsciousSpendingGuideline.savings.score(30), -1);
  });
}
