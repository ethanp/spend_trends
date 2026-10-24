import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/features/activity/overlapping_merchant_contains_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const categoryNames = {'cat_groceries': 'Groceries', 'cat_dining': 'Dining'};

  CategorizationRule containsRule(
    String pattern, {
    String categoryId = 'cat_groceries',
  }) {
    return CategorizationRule(
      id: 'rule_$pattern',
      matchType: RuleMatchType.merchantContains,
      pattern: pattern,
      categoryId: categoryId,
    );
  }

  group('overlappingMerchantContainsRules', () {
    test('returns empty for blank candidate', () {
      expect(
        overlappingMerchantContainsRules(
          candidatePattern: '  ',
          existingRules: [containsRule('kroger')],
          categoryNameById: categoryNames,
        ),
        isEmpty,
      );
    });

    test('classifies same, broader, and narrower overlaps', () {
      final related = overlappingMerchantContainsRules(
        candidatePattern: 'Kroger Fuel',
        existingRules: [
          containsRule('kroger fuel'),
          containsRule('kroger'),
          containsRule('kroger fuel center', categoryId: 'cat_dining'),
          containsRule('costco'),
        ],
        categoryNameById: categoryNames,
      );

      expect(related.map((entry) => entry.relation).toList(), [
        RelatedRuleRelation.same,
        RelatedRuleRelation.broader,
        RelatedRuleRelation.narrower,
      ]);
      expect(related.map((entry) => entry.rule.pattern).toList(), [
        'kroger fuel',
        'kroger',
        'kroger fuel center',
      ]);
      expect(related[2].categoryName, 'Dining');
    });

    test('ignores non-contains rules', () {
      final related = overlappingMerchantContainsRules(
        candidatePattern: 'amazon',
        existingRules: [
          const CategorizationRule(
            id: 'exact',
            matchType: RuleMatchType.merchantExact,
            pattern: 'amazon',
            categoryId: 'cat_groceries',
          ),
        ],
        categoryNameById: categoryNames,
      );
      expect(related, isEmpty);
    });
  });
}
