import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/rule_change_plan.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:uuid/uuid.dart';

/// Categories come only from rules. Every change to rules goes through
/// [planRuleChanges] (dry run) and [applyRuleChanges] (write rules, then the
/// transactions they move).
class Categorizer({
  required final CategoriesRepository _categoriesRepository,
  required final TransactionsRepository _transactionsRepository,
}) {
  final _uuid = const Uuid();

  Future<RuleChangePlan> planRuleChanges({
    List<RuleDraft> drafts = const [],
    Set<String> deletedRuleIds = const {},
  }) async {
    final rulesBefore = await _categoriesRepository.listRules();
    return RuleChangePlan(
      rulesBefore: rulesBefore,
      transactions: await _transactionsRepository.listAll(),
      upserts: _rulesFor(drafts, rulesBefore),
      deletedRuleIds: deletedRuleIds,
    );
  }

  Future<RuleChangePlan> applyRuleChanges({
    List<RuleDraft> drafts = const [],
    Set<String> deletedRuleIds = const {},
  }) async {
    final plan = await planRuleChanges(
      drafts: drafts,
      deletedRuleIds: deletedRuleIds,
    );
    await _categoriesRepository.writeRuleChanges(
      upserts: plan.upserts,
      deletedRuleIds: deletedRuleIds,
    );
    await _transactionsRepository.setCategories(plan.recategorized);
    return plan;
  }

  /// Transactions [draft] would newly take: ones it matches where no more
  /// specific rule wins and it is not already their rule. The draft's
  /// category does not matter.
  Future<List<BankTransaction>> transactionsClaimedBy(RuleDraft draft) async {
    final plan = await planRuleChanges(drafts: [draft]);
    final claimingRuleId = plan.upserts.single.id;
    return [
      for (final move in plan.recategorized)
        if (move.rule?.id == claimingRuleId) move.transaction,
    ];
  }

  /// Writes the note (null or blank clears it), then re-runs the rules over
  /// that one transaction: a contains rule can match the note, so this is how
  /// one transaction takes a category its bank text never would.
  Future<RuleChangePlan> setNote({
    required String transactionId,
    required String? note,
  }) async {
    await _transactionsRepository.setNote(
      transactionId: transactionId,
      note: note,
    );
    return _rerunRulesOn({transactionId});
  }

  /// [setNote] for many transactions, with one pass of the rules at the end.
  Future<RuleChangePlan> setNotes(
    Map<String, String> noteByTransactionId,
  ) async {
    await _transactionsRepository.setNotes(noteByTransactionId);
    return _rerunRulesOn(noteByTransactionId.keys.toSet());
  }

  Future<RuleChangePlan> _rerunRulesOn(Set<String> transactionIds) async {
    final plan = RuleChangePlan(
      rulesBefore: await _categoriesRepository.listRules(),
      transactions: await _transactionsRepository.listByIds(transactionIds),
      reconsiderAll: true,
    );
    await _transactionsRepository.setCategories(plan.recategorized);
    return plan;
  }

  /// Re-runs every rule over every transaction, e.g. after a bank pull.
  Future<RuleChangePlan> recategorizeAll() async {
    final plan = RuleChangePlan(
      rulesBefore: await _categoriesRepository.listRules(),
      transactions: await _transactionsRepository.listAll(),
      reconsiderAll: true,
    );
    await _transactionsRepository.setCategories(plan.recategorized);
    return plan;
  }

  List<CategorizationRule> _rulesFor(
    List<RuleDraft> drafts,
    List<CategorizationRule> rulesBefore,
  ) {
    return [for (final draft in drafts) _ruleFor(draft, rulesBefore)];
  }

  CategorizationRule _ruleFor(
    RuleDraft draft,
    List<CategorizationRule> rulesBefore,
  ) {
    if (draft.matchType.usesPattern && draft.normalizedPattern.isEmpty) {
      throw ArgumentError('Rule pattern is required.');
    }
    if (!draft.matchType.usesPattern && draft.accountId == null) {
      throw ArgumentError('A whole-account rule needs an accountId.');
    }
    final CategorizationRule? sameMatch = draft.updatedRuleIn(rulesBefore);
    return draft.asRule(id: sameMatch?.id ?? _uuid.v4(), existing: sameMatch);
  }
}
