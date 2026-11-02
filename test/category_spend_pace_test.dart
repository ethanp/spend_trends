import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_spend_pace.dart';
import 'package:spend_trends/domain/transaction.dart';

void main() {
  final now = DateTime(2026, 11, 1, 12);
  const dining = SpendCategory(
    id: 'cat_dining',
    name: 'Dining',
    sortOrder: 0,
    archived: false,
  );

  BankTransaction diningSpend(DateTime postedAt, int dollars) =>
      BankTransaction(
        id: 'txn_${postedAt.millisecondsSinceEpoch}',
        accountId: 'acct',
        externalId: 'ext_${postedAt.millisecondsSinceEpoch}',
        postedAtMillis: postedAt.millisecondsSinceEpoch,
        amountCents: -dollars * 100,
        rawDescription: 'Dinner',
        normalizedMerchant: 'Dinner',
        pending: false,
        categoryId: dining.id,
      );

  test('each window averages only the spend inside it, per month', () {
    final CategorySpendPace diningPace = CategorySpendPace.forCategories(
      now: now,
      transactions: [
        diningSpend(DateTime(2026, 10, 15), 300),
        diningSpend(DateTime(2026, 3, 1), 600),
        diningSpend(DateTime(2025, 3, 1), 1200),
      ],
      categories: const [dining],
    ).single;

    expect(diningPace.monthlyCents(CategorySpendWindow.threeMonths), 10027);
    expect(diningPace.monthlyCents(CategorySpendWindow.sixMonths), 4986);
    expect(diningPace.monthlyCents(CategorySpendWindow.oneYear), 7500);
    expect(diningPace.monthlyCents(CategorySpendWindow.twoYears), 8750);
  });

  test('a category with no spend reads zero in every window', () {
    final CategorySpendPace diningPace = CategorySpendPace.forCategories(
      now: now,
      transactions: const [],
      categories: const [dining],
    ).single;

    for (final window in CategorySpendWindow.values) {
      expect(diningPace.monthlyCents(window), 0);
    }
  });
}
