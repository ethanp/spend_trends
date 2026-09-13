import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/rule_match_index.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuleMatchIndex.bestMatchingRule', () {
    test('prefers longer contains pattern over shorter prefix', () {
      const groceryRule = CategorizationRule(
        id: 'grocery',
        matchType: RuleMatchType.merchantContains,
        pattern: 'kroger',
        categoryId: 'groceries',
        priority: 10,
      );
      const fuelRule = CategorizationRule(
        id: 'fuel',
        matchType: RuleMatchType.merchantContains,
        pattern: 'kroger fuel',
        categoryId: 'transport',
        priority: 10,
      );
      // Alphabetical order would try "kroger" before "kroger fuel".
      final rules = [groceryRule, fuelRule];
      final index = RuleMatchIndex(rules);

      final fuelTxn = _txn(merchant: 'KROGER FUEL');
      final groceryTxn = _txn(merchant: 'KROGER');

      expect(index.bestMatchingRule(fuelTxn)?.categoryId, 'transport');
      expect(index.bestMatchingRule(groceryTxn)?.categoryId, 'groceries');
    });

    test('higher priority still beats a longer pattern', () {
      final rules = [
        const CategorizationRule(
          id: 'long',
          matchType: RuleMatchType.merchantContains,
          pattern: 'kroger fuel',
          categoryId: 'transport',
          priority: 10,
        ),
        const CategorizationRule(
          id: 'short',
          matchType: RuleMatchType.merchantContains,
          pattern: 'kroger',
          categoryId: 'groceries',
          priority: 20,
        ),
      ];

      expect(
        RuleMatchIndex(rules)
            .bestMatchingRule(_txn(merchant: 'KROGER FUEL'))
            ?.categoryId,
        'groceries',
      );
    });
  });

  group('RuleMatchIndex.coveredByBetterExistingRule', () {
    const fuelRule = CategorizationRule(
      id: 'fuel',
      matchType: RuleMatchType.merchantContains,
      pattern: 'kroger fuel',
      categoryId: 'transport',
      priority: 10,
    );
    const groceryProposed = CategorizationRule(
      id: '_proposed_',
      matchType: RuleMatchType.merchantContains,
      pattern: 'kroger',
      categoryId: '_proposed_',
      priority: 10,
    );
    final existingIndex = RuleMatchIndex([fuelRule]);

    test('skips fuel txn when proposing shorter kroger pattern', () {
      expect(
        existingIndex.coveredByBetterExistingRule(
          transaction: _txn(merchant: 'KROGER FUEL'),
          proposedRule: groceryProposed,
        ),
        isTrue,
      );
    });

    test('keeps plain kroger txn for shorter pattern', () {
      expect(
        existingIndex.coveredByBetterExistingRule(
          transaction: _txn(merchant: 'KROGER'),
          proposedRule: groceryProposed,
        ),
        isFalse,
      );
    });

    test('does not treat same-pattern existing rule as covering', () {
      const existingGrocery = CategorizationRule(
        id: 'grocery',
        matchType: RuleMatchType.merchantContains,
        pattern: 'kroger',
        categoryId: 'groceries',
        priority: 10,
      );
      expect(
        RuleMatchIndex([existingGrocery, fuelRule]).coveredByBetterExistingRule(
          transaction: _txn(merchant: 'KROGER'),
          proposedRule: groceryProposed,
        ),
        isFalse,
      );
    });

    test('still skips fuel when same-pattern grocery rule already exists', () {
      const existingGrocery = CategorizationRule(
        id: 'grocery',
        matchType: RuleMatchType.merchantContains,
        pattern: 'kroger',
        categoryId: 'groceries',
        priority: 10,
      );
      expect(
        RuleMatchIndex([existingGrocery, fuelRule]).coveredByBetterExistingRule(
          transaction: _txn(merchant: 'KROGER FUEL'),
          proposedRule: groceryProposed,
        ),
        isTrue,
      );
    });

    test('skips when higher-priority shorter rule already wins', () {
      const priorityFuel = CategorizationRule(
        id: 'fuel-priority',
        matchType: RuleMatchType.merchantContains,
        pattern: 'fuel',
        categoryId: 'transport',
        priority: 50,
      );
      expect(
        RuleMatchIndex([priorityFuel]).coveredByBetterExistingRule(
          transaction: _txn(merchant: 'KROGER FUEL'),
          proposedRule: groceryProposed,
        ),
        isTrue,
      );
    });
  });

  group('RuleMatchIndex.explainingRule', () {
    test('lists only transactions where the rule is primary', () {
      const groceryRule = CategorizationRule(
        id: 'grocery',
        matchType: RuleMatchType.merchantContains,
        pattern: 'kroger',
        categoryId: 'groceries',
        priority: 10,
      );
      const fuelRule = CategorizationRule(
        id: 'fuel',
        matchType: RuleMatchType.merchantContains,
        pattern: 'kroger fuel',
        categoryId: 'transport',
        priority: 10,
      );
      final index = RuleMatchIndex([groceryRule, fuelRule]);

      final groceryTxn = _txn(
        id: 'g1',
        merchant: 'KROGER',
        suggestedCategoryId: 'groceries',
      );
      final fuelTxn = _txn(
        id: 'f1',
        merchant: 'KROGER FUEL',
        suggestedCategoryId: 'transport',
      );
      final wrongCategoryTxn = _txn(
        id: 'w1',
        merchant: 'KROGER',
        userCategoryId: 'dining',
      );

      final primaryForGrocery = [
        for (final transaction in [groceryTxn, fuelTxn, wrongCategoryTxn])
          if (index.explainingRule(transaction)?.id == groceryRule.id)
            transaction.id,
      ];
      expect(primaryForGrocery, ['g1']);

      final primaryForFuel = [
        for (final transaction in [groceryTxn, fuelTxn, wrongCategoryTxn])
          if (index.explainingRule(transaction)?.id == fuelRule.id)
            transaction.id,
      ];
      expect(primaryForFuel, ['f1']);
    });
  });
}

BankTransaction _txn({
  required String merchant,
  String id = 't1',
  String? userCategoryId,
  String? suggestedCategoryId,
}) {
  return BankTransaction(
    id: id,
    accountId: 'a1',
    externalId: 'e1',
    postedAt: DateTime(2024, 1, 1),
    amountCents: -1000,
    rawDescription: merchant,
    normalizedMerchant: merchant,
    pending: false,
    userCategoryId: userCategoryId,
    suggestedCategoryId: suggestedCategoryId,
  );
}
