import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/data/repositories/categories_repository.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/rule_change_plan.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/use_cases/categories/categorizer.dart';

class _FixedRulesRepository(final List<CategorizationRule> rules)
    implements CategoriesRepository {
  @override
  Future<List<CategorizationRule>> listRules() async => rules;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedTransactionsRepository(final List<BankTransaction> transactions)
    implements TransactionsRepository {
  @override
  Future<List<BankTransaction>> listAll({int? limit}) async => transactions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _shoppingTimHoWanRule = CategorizationRule(
  id: 'tim-ho-wan-shopping',
  matchType: RuleMatchType.merchantContains,
  pattern: 'tim ho wan',
  categoryId: 'shopping',
  note: "Backfilled from Copilot's import category (Shopping); not reviewed.",
);

final _timHoWanTransaction = BankTransaction(
  id: 't1',
  accountId: 'card',
  externalId: 'e1',
  postedAtMillis: DateTime(2026, 3, 1).millisecondsSinceEpoch,
  amountCents: -3200,
  rawDescription: 'TIM HO WAN HOUSTON - K',
  normalizedMerchant: 'TIM HO WAN HOUSTON - K',
  pending: false,
  categoryId: 'shopping',
  categoryRuleId: 'tim-ho-wan-shopping',
);

void main() {
  test(
    'a rule re-added in the change that deletes it becomes a new rule',
    () async {
      final categorizer = Categorizer(
        categoriesRepository: _FixedRulesRepository(const [
          _shoppingTimHoWanRule,
        ]),
        transactionsRepository: _FixedTransactionsRepository([
          _timHoWanTransaction,
        ]),
      );

      final RuleChangePlan plan = await categorizer.planRuleChanges(
        drafts: const [RuleDraft(pattern: 'tim ho wan', categoryId: 'dining')],
        deletedRuleIds: {_shoppingTimHoWanRule.id},
      );

      final CategorizationRule diningRule = plan.upserts.single;
      expect(diningRule.id, isNot(_shoppingTimHoWanRule.id));
      expect(diningRule.note, isNull);
      expect(plan.recategorized.single.rule?.id, diningRule.id);
      expect(plan.recategorized.single.categoryId, 'dining');
    },
  );
}
