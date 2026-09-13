import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/rule_match_index.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:uuid/uuid.dart';

class Categorizer({
  required final CategoriesRepository _categoriesRepository,
  required final TransactionsRepository _transactionsRepository,
}) {
  final _uuid = const Uuid();

  Future<String?> resolveCategoryId(BankTransaction transaction) async {
    if (transaction.hasUserCategory) {
      return transaction.userCategoryId;
    }

    final rules = await _categoriesRepository.listRules();
    final matchingRule = RuleMatchIndex(rules).bestMatchingRule(transaction);
    if (matchingRule != null) return matchingRule.categoryId;

    return transaction.suggestedCategoryId;
  }

  Future<void> assignUserCategory({
    required String transactionId,
    required String categoryId,
    required bool createRule,
    String? containsPattern,
    Set<String> alsoApplyToTransactionIds = const {},
  }) async {
    await _transactionsRepository.setUserCategory(
      transactionId: transactionId,
      categoryId: categoryId,
    );
    if (!createRule) return;

    final pattern = containsPattern?.trim() ?? '';
    if (pattern.isEmpty) {
      throw ArgumentError('Rule pattern is required when creating a rule.');
    }

    await _upsertContainsRule(pattern: pattern, categoryId: categoryId);
    for (final otherTransactionId in alsoApplyToTransactionIds) {
      if (otherTransactionId == transactionId) continue;
      await _transactionsRepository.setUserCategory(
        transactionId: otherTransactionId,
        categoryId: categoryId,
      );
    }
  }

  Future<List<BankTransaction>> transactionsMatchingContains(
    String pattern,
  ) async {
    final normalizedPattern = pattern.trim();
    final proposedRule = CategorizationRule(
      id: '_proposed_',
      matchType: RuleMatchType.merchantContains,
      pattern: normalizedPattern,
      categoryId: '_proposed_',
      priority: CategorizationRule.userCreatedPriority,
    );
    final transactions = await _transactionsRepository.listAll();
    final existingRules = await _categoriesRepository.listRules();
    final existingIndex = RuleMatchIndex(existingRules);
    return [
      for (final transaction in transactions)
        if (RuleMatchIndex.ruleMatches(transaction, proposedRule) &&
            !existingIndex.coveredByBetterExistingRule(
              transaction: transaction,
              proposedRule: proposedRule,
            ))
          transaction,
    ];
  }

  /// Upserts a case-insensitive contains rule for [pattern] → [categoryId].
  Future<void> upsertMerchantContainsRule({
    required String pattern,
    required String categoryId,
  }) => _upsertContainsRule(pattern: pattern, categoryId: categoryId);

  Future<void> applyCategoryToTransactions({
    required String categoryId,
    required Iterable<String> transactionIds,
    required bool asUserCategory,
  }) async {
    for (final transactionId in transactionIds) {
      if (asUserCategory) {
        await _transactionsRepository.setUserCategory(
          transactionId: transactionId,
          categoryId: categoryId,
        );
      } else {
        await _transactionsRepository.setSuggestedCategory(
          transactionId: transactionId,
          categoryId: categoryId,
        );
      }
    }
  }

  Future<void> _upsertContainsRule({
    required String pattern,
    required String categoryId,
  }) async {
    final normalizedPattern = pattern.trim().toLowerCase();
    final rules = await _categoriesRepository.listRules();
    for (final rule in rules) {
      if (rule.matchType != RuleMatchType.merchantContains) continue;
      if (rule.pattern.trim().toLowerCase() != normalizedPattern) continue;
      await _categoriesRepository.upsertRule(
        CategorizationRule(
          id: rule.id,
          matchType: RuleMatchType.merchantContains,
          pattern: normalizedPattern,
          categoryId: categoryId,
          priority: rule.priority,
        ),
      );
      return;
    }

    await _categoriesRepository.upsertRule(
      CategorizationRule(
        id: _uuid.v4(),
        matchType: RuleMatchType.merchantContains,
        pattern: normalizedPattern,
        categoryId: categoryId,
        priority: CategorizationRule.userCreatedPriority,
      ),
    );
  }

  Future<void> applyRulesToUncategorized({
    void Function(int completed, int total)? onProgress,
  }) async {
    final transactions = await _transactionsRepository.listAll();
    final rules = await _categoriesRepository.listRules();
    final ruleMatchIndex = RuleMatchIndex(rules);
    final total = transactions.length;
    for (var index = 0; index < transactions.length; index++) {
      final transaction = transactions[index];
      onProgress?.call(index + 1, total);
      if (transaction.hasUserCategory) continue;

      final matchingRule = ruleMatchIndex.bestMatchingRule(transaction);
      if (matchingRule == null) continue;
      if (matchingRule.categoryId == transaction.suggestedCategoryId) continue;

      await _transactionsRepository.setSuggestedCategory(
        transactionId: transaction.id,
        categoryId: matchingRule.categoryId,
      );
    }
  }

  /// Transactions whose effective category is explained by [rule] as primary.
  Future<List<BankTransaction>> transactionsExplainedByRule(
    CategorizationRule rule,
  ) async {
    final transactions = await _transactionsRepository.listAll();
    final rules = await _categoriesRepository.listRules();
    final ruleMatchIndex = RuleMatchIndex(rules);
    return [
      for (final transaction in transactions)
        if (ruleMatchIndex.explainingRule(transaction)?.id == rule.id)
          transaction,
    ];
  }

  /// Deletes [rule], clears categories on its primary matches, and reapplies
  /// remaining rules to those transactions as suggested categories.
  Future<RemoveRuleReclaimResult> removeRuleAndReclaim(
    CategorizationRule rule,
  ) async {
    final primaryMatches = await transactionsExplainedByRule(rule);
    for (final transaction in primaryMatches) {
      await _transactionsRepository.setUserCategory(
        transactionId: transaction.id,
        categoryId: null,
      );
      await _transactionsRepository.setSuggestedCategory(
        transactionId: transaction.id,
        categoryId: null,
      );
    }

    await _categoriesRepository.deleteRule(rule.id);

    final remainingRules = await _categoriesRepository.listRules();
    final ruleMatchIndex = RuleMatchIndex(remainingRules);
    var reclaimedCount = 0;
    for (final transaction in primaryMatches) {
      final matchingRule = ruleMatchIndex.bestMatchingRule(transaction);
      if (matchingRule == null) continue;
      await _transactionsRepository.setSuggestedCategory(
        transactionId: transaction.id,
        categoryId: matchingRule.categoryId,
      );
      reclaimedCount++;
    }

    return RemoveRuleReclaimResult(
      clearedTransactionCount: primaryMatches.length,
      reclaimedByOtherRulesCount: reclaimedCount,
    );
  }

  /// Points [rule] at [categoryId] and updates its primary matches to match.
  Future<int> retargetRule({
    required CategorizationRule rule,
    required String categoryId,
  }) async {
    if (categoryId == rule.categoryId) return 0;

    final primaryMatches = await transactionsExplainedByRule(rule);
    await _categoriesRepository.upsertRule(
      CategorizationRule(
        id: rule.id,
        matchType: rule.matchType,
        pattern: rule.pattern,
        categoryId: categoryId,
        priority: rule.priority,
      ),
    );

    for (final transaction in primaryMatches) {
      if (transaction.userCategoryId == rule.categoryId) {
        await _transactionsRepository.setUserCategory(
          transactionId: transaction.id,
          categoryId: categoryId,
        );
      } else {
        await _transactionsRepository.setSuggestedCategory(
          transactionId: transaction.id,
          categoryId: categoryId,
        );
      }
    }

    return primaryMatches.length;
  }
}

class const RemoveRuleReclaimResult({
  required final int clearedTransactionCount,
  required final int reclaimedByOtherRulesCount,
});
