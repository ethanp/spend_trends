import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers.dart';

void main() {
  BankTransaction transaction(
    String id,
    DateTime postedAt,
    int cents,
    String categoryId,
  ) => BankTransaction(
    id: id,
    accountId: 'checking',
    externalId: id,
    postedAt: postedAt,
    amountCents: cents,
    rawDescription: id,
    normalizedMerchant: id,
    pending: false,
    categoryId: categoryId,
  );

  test('each window is a plain total over its days ending today', () {
    final today = DateTime(2026, 10, 24);
    final numbers = ConsciousSpendingNumbers.endingOn(
      today: today,
      accounts: const [],
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
        transaction('yearStart', DateTime(2025, 10, 25), -10000, 'cat_dining'),
        transaction(
          'justOutsideYear',
          DateTime(2025, 10, 24),
          -50000,
          'cat_dining',
        ),
        transaction('today', DateTime(2026, 10, 24, 18), -15000, 'cat_dining'),
        transaction('tomorrow', DateTime(2026, 10, 25), -99999, 'cat_dining'),
      ],
    );

    final lastYear = numbers.totalsFor(ConsciousSpendingWindow.oneYear);
    expect(lastYear.firstDay, DateTime(2025, 10, 25));
    expect(lastYear.takeHomeCents, 100000);
    expect(lastYear.centsByArea[ConsciousSpendingArea.guiltFree], 25000);
    expect(lastYear.percentOfTakeHome(ConsciousSpendingArea.guiltFree), 25);

    final lastTwoYears = numbers.totalsFor(ConsciousSpendingWindow.twoYears);
    expect(lastTwoYears.takeHomeCents, 200000);
    expect(lastTwoYears.centsByArea[ConsciousSpendingArea.guiltFree], 75000);
    expect(lastTwoYears.annualCents(ConsciousSpendingArea.guiltFree), 37500);

    final lastSixMonths = numbers.totalsFor(ConsciousSpendingWindow.sixMonths);
    expect(lastSixMonths.firstDay, DateTime(2026, 4, 25));
    expect(lastSixMonths.centsByArea[ConsciousSpendingArea.guiltFree], 15000);
    expect(numbers.periodLabel, '2y · 1y · 6mo ending Oct 24, 2026');
  });

  test('guideline score: 0 in range, toward 1 when beaten, -1 when missed', () {
    expect(ConsciousSpendingArea.fixedCosts.ramitGuideline.score(55), 0);
    expect(ConsciousSpendingArea.fixedCosts.ramitGuideline.score(40), 0.5);
    expect(ConsciousSpendingArea.fixedCosts.ramitGuideline.score(82), -1);
    expect(ConsciousSpendingArea.investments.ramitGuideline.score(44), 1);
    expect(ConsciousSpendingArea.investments.ramitGuideline.score(4), -0.3);
    expect(ConsciousSpendingArea.guiltFree.ramitGuideline.score(14), 0.3);
  });
}
