import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/activity_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activityMatchesSearch', () {
    final krogerFuel = BankTransaction(
      id: '1',
      accountId: 'a1',
      externalId: 'e1',
      postedAtMillis: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      amountCents: -4523,
      rawDescription: 'KROGER FUEL 123',
      normalizedMerchant: 'KROGER FUEL',
      pending: false,
      note: 'fill up',
    );
    const checking = Account(
      id: 'a1',
      externalId: 'ext',
      name: 'Chase Checking',
      currency: 'USD',
      balanceCents: 0,
      status: AccountStatus.ok,
    );
    const transport = SpendCategory(
      id: 'c1',
      name: 'Transport',
      sortOrder: 0,
      archived: false,
    );

    test('empty query matches everything', () {
      expect(
        activityMatchesSearch(transaction: krogerFuel, query: '  '),
        isTrue,
      );
    });

    test('ANDs space-separated terms case-insensitively', () {
      expect(
        activityMatchesSearch(
          transaction: krogerFuel,
          query: 'kroger fuel',
          account: checking,
          category: transport,
        ),
        isTrue,
      );
      expect(
        activityMatchesSearch(
          transaction: krogerFuel,
          query: 'kroger grocery',
          category: transport,
        ),
        isFalse,
      );
    });

    test('matches across description, category, account, note, amount', () {
      expect(
        activityMatchesSearch(
          transaction: krogerFuel,
          query: 'transport chase fill 45.23',
          account: checking,
          category: transport,
        ),
        isTrue,
      );
    });
  });
}
