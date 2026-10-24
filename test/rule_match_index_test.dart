import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/rule_change_plan.dart';
import 'package:spend_trends/domain/rule_match_index.dart';
import 'package:spend_trends/domain/transaction.dart';

void main() {
  BankTransaction transaction({
    required String id,
    required String description,
    String accountId = 'checking',
    String? categoryId,
    String? categoryRuleId,
  }) => BankTransaction(
    id: id,
    accountId: accountId,
    externalId: id,
    postedAt: DateTime(2026, 1, 1),
    amountCents: -1000,
    rawDescription: description,
    normalizedMerchant: description.toUpperCase(),
    pending: false,
    categoryId: categoryId,
    categoryRuleId: categoryRuleId,
  );

  CategorizationRule rule({
    required String id,
    required String pattern,
    required String categoryId,
    RuleMatchType matchType = RuleMatchType.merchantContains,
    String? accountId,
  }) => CategorizationRule(
    id: id,
    matchType: matchType,
    pattern: pattern,
    categoryId: categoryId,
    accountId: accountId,
  );

  group('RuleMatchIndex.bestMatchingRule picks the most specific rule', () {
    final kroger = rule(
      id: 'kroger',
      pattern: 'kroger',
      categoryId: 'groceries',
    );
    final krogerFuel = rule(
      id: 'kroger-fuel',
      pattern: 'kroger fuel',
      categoryId: 'transport',
    );

    test('longer contains pattern beats a shorter one', () {
      final index = RuleMatchIndex([kroger, krogerFuel]);
      expect(
        index.bestMatchingRule(
          transaction(id: 'fuel', description: 'Kroger Fuel #12'),
        ),
        krogerFuel,
      );
      expect(
        index.bestMatchingRule(transaction(id: 'groc', description: 'Kroger')),
        kroger,
      );
    });

    test('one-account rule beats an all-accounts rule', () {
      final buyAnywhere = rule(
        id: 'buy',
        pattern: 'buy',
        categoryId: 'shopping',
      );
      final buyAtBrokerage = rule(
        id: 'buy-brokerage',
        pattern: 'buy',
        categoryId: 'transfer',
        accountId: 'brokerage',
      );
      final index = RuleMatchIndex([buyAnywhere, buyAtBrokerage]);
      expect(
        index.bestMatchingRule(
          transaction(id: 't', description: 'Buy LQD', accountId: 'brokerage'),
        ),
        buyAtBrokerage,
      );
      expect(
        index.bestMatchingRule(
          transaction(id: 'c', description: 'Buy Buy Baby'),
        ),
        buyAnywhere,
      );
    });

    test('exact match beats a longer contains pattern', () {
      final amazonExact = rule(
        id: 'amazon-exact',
        pattern: 'amazon',
        categoryId: 'shopping',
        matchType: RuleMatchType.merchantExact,
      );
      final amazonPrime = rule(
        id: 'prime',
        pattern: 'amazon',
        categoryId: 'utilities',
      );
      final index = RuleMatchIndex([amazonPrime, amazonExact]);
      expect(
        index.bestMatchingRule(transaction(id: 'a', description: 'Amazon')),
        amazonExact,
      );
      expect(
        index.bestMatchingRule(
          transaction(id: 'p', description: 'Amazon Prime'),
        ),
        amazonPrime,
      );
    });
  });

  group('RuleChangePlan', () {
    final kroger = rule(
      id: 'kroger',
      pattern: 'kroger',
      categoryId: 'shopping',
    );
    final plainKroger = transaction(
      id: 'plain',
      description: 'Kroger',
      categoryId: 'shopping',
      categoryRuleId: 'kroger',
    );
    final krogerFuel = transaction(
      id: 'fuel',
      description: 'Kroger Fuel',
      categoryId: 'shopping',
      categoryRuleId: 'kroger',
    );
    final unrelated = transaction(
      id: 'other',
      description: 'Shell',
      categoryId: 'transport',
    );

    test('a narrower new rule takes only what it matches', () {
      final plan = RuleChangePlan(
        rulesBefore: [kroger],
        transactions: [plainKroger, krogerFuel, unrelated],
        upserts: [
          rule(
            id: 'fuel-rule',
            pattern: 'kroger fuel',
            categoryId: 'transport',
          ),
        ],
      );
      expect(plan.recategorized.map((move) => move.transaction.id), ['fuel']);
      expect(plan.categoryChanges.single.categoryId, 'transport');
    });

    test('retargeting a rule moves everything it categorizes', () {
      final plan = RuleChangePlan(
        rulesBefore: [kroger],
        transactions: [plainKroger, krogerFuel, unrelated],
        upserts: [kroger.copyWith(categoryId: 'groceries')],
      );
      expect(plan.categoryChanges.map((move) => move.transaction.id), [
        'plain',
        'fuel',
      ]);
    });

    test('deleting a rule uncategorizes what no other rule matches', () {
      final plan = RuleChangePlan(
        rulesBefore: [kroger],
        transactions: [plainKroger, unrelated],
        deletedRuleIds: {'kroger'},
      );
      expect(plan.categoryChanges.single.transaction.id, 'plain');
      expect(plan.categoryChanges.single.categoryId, isNull);
    });

    test('a rule-less legacy category is left alone unless a rule matches', () {
      final plan = RuleChangePlan(
        rulesBefore: [kroger],
        transactions: [unrelated],
        upserts: [
          rule(
            id: 'fuel-rule',
            pattern: 'kroger fuel',
            categoryId: 'transport',
          ),
        ],
      );
      expect(plan.recategorized, isEmpty);
    });

    test('a draft resolves to the rule with the same match', () {
      const draft = RuleDraft(pattern: ' Kroger ', categoryId: 'groceries');
      expect(draft.sameMatchAs(kroger), isTrue);
      expect(
        draft.matches(transaction(id: 'k', description: 'KROGER #320')),
        isTrue,
      );
    });
  });

  test(
    'a whole-account rule matches blank descriptions, losing to text rules',
    () {
      final stakingAccount = rule(
        id: 'staking',
        pattern: '',
        categoryId: 'income',
        matchType: RuleMatchType.wholeAccount,
        accountId: 'staked-eth',
      );
      final rewardText = rule(
        id: 'reward',
        pattern: 'reward',
        categoryId: 'transfer',
        accountId: 'staked-eth',
      );
      final index = RuleMatchIndex([stakingAccount, rewardText]);
      expect(
        index.bestMatchingRule(
          transaction(id: 'blank', description: '', accountId: 'staked-eth'),
        ),
        stakingAccount,
      );
      expect(
        index.bestMatchingRule(
          transaction(
            id: 'named',
            description: 'Reward',
            accountId: 'staked-eth',
          ),
        ),
        rewardText,
      );
      expect(
        index.bestMatchingRule(transaction(id: 'elsewhere', description: '')),
        isNull,
      );
    },
  );
}
