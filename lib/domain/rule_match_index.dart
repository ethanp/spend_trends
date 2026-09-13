import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';

/// Pre-normalized rules for repeated matching without re-trimming patterns.
class RuleMatchIndex(List<CategorizationRule> rules) {
  final List<_PreparedRule> _preparedRules = _prepareRules(rules);

  CategorizationRule? bestMatchingRule(BankTransaction transaction) {
    if (_preparedRules.isEmpty) return null;
    final merchantLower = transaction.normalizedMerchant.toLowerCase();
    final descriptionLower = transaction.rawDescription.trim().toLowerCase();
    final haystack = '$descriptionLower\n$merchantLower';

    _PreparedRule? bestPrepared;
    for (final prepared in _preparedRules) {
      if (!_preparedRuleMatches(
        matchType: prepared.rule.matchType,
        pattern: prepared.pattern,
        merchantLower: merchantLower,
        descriptionLower: descriptionLower,
        haystack: haystack,
      )) {
        continue;
      }
      if (bestPrepared == null ||
          _isBetterPreparedRule(prepared, bestPrepared)) {
        bestPrepared = prepared;
      }
    }
    return bestPrepared?.rule;
  }

  CategorizationRule? explainingRule(BankTransaction transaction) {
    if (transaction.isUncategorized) return null;
    final matchingRule = bestMatchingRule(transaction);
    if (matchingRule == null) return null;
    if (matchingRule.categoryId != transaction.effectiveCategoryId) return null;
    return matchingRule;
  }

  /// Explaining rule for each transaction (one shared prepared-rule list).
  Map<String, CategorizationRule?> explainingRulesByTransactionId(
    Iterable<BankTransaction> transactions,
  ) {
    return {
      for (final transaction in transactions)
        transaction.id: explainingRule(transaction),
    };
  }

  /// Case-insensitive match of [rule] against the transaction description.
  static bool ruleMatches(
    BankTransaction transaction,
    CategorizationRule rule,
  ) {
    final pattern = rule.pattern.trim().toLowerCase();
    if (pattern.isEmpty) return false;
    final merchantLower = transaction.normalizedMerchant.toLowerCase();
    final descriptionLower = transaction.rawDescription.trim().toLowerCase();
    return _preparedRuleMatches(
      matchType: rule.matchType,
      pattern: pattern,
      merchantLower: merchantLower,
      descriptionLower: descriptionLower,
      haystack: '$descriptionLower\n$merchantLower',
    );
  }

  /// True when a competing existing rule would beat [proposedRule].
  ///
  /// Used so “apply rule to existing” does not overwrite a more-specific (or
  /// otherwise better) rule that already matches — e.g. proposing `kroger`
  /// skips txs where `kroger fuel` already wins. An existing rule with the
  /// same pattern is ignored (upsert / re-apply of that rule).
  bool coveredByBetterExistingRule({
    required BankTransaction transaction,
    required CategorizationRule proposedRule,
  }) {
    if (!ruleMatches(transaction, proposedRule)) return false;
    final competingRules = [
      for (final prepared in _preparedRules)
        if (!_sameContainsPattern(prepared.rule, proposedRule)) prepared.rule,
      proposedRule,
    ];
    final winner = RuleMatchIndex(competingRules).bestMatchingRule(transaction);
    return winner?.id != proposedRule.id;
  }

  static List<_PreparedRule> _prepareRules(List<CategorizationRule> rules) {
    final preparedRules = <_PreparedRule>[];
    for (final rule in rules) {
      final pattern = rule.pattern.trim().toLowerCase();
      if (pattern.isEmpty) continue;
      preparedRules.add(
        _PreparedRule(
          rule: rule,
          pattern: pattern,
          patternLength: pattern.length,
        ),
      );
    }
    return preparedRules;
  }

  static bool _preparedRuleMatches({
    required RuleMatchType matchType,
    required String pattern,
    required String merchantLower,
    required String descriptionLower,
    required String haystack,
  }) {
    switch (matchType) {
      case RuleMatchType.merchantExact:
        return merchantLower == pattern || descriptionLower == pattern;
      case RuleMatchType.merchantContains:
        return haystack.contains(pattern);
    }
  }

  static bool _isBetterPreparedRule(
    _PreparedRule candidate,
    _PreparedRule incumbent,
  ) {
    if (candidate.rule.priority != incumbent.rule.priority) {
      return candidate.rule.priority > incumbent.rule.priority;
    }
    if (candidate.patternLength != incumbent.patternLength) {
      return candidate.patternLength > incumbent.patternLength;
    }
    if (candidate.rule.matchType != incumbent.rule.matchType) {
      return candidate.rule.matchType == RuleMatchType.merchantExact;
    }
    return candidate.pattern.compareTo(incumbent.pattern) < 0;
  }

  static bool _sameContainsPattern(
    CategorizationRule rule,
    CategorizationRule proposedRule,
  ) {
    if (rule.matchType != proposedRule.matchType) return false;
    return rule.pattern.trim().toLowerCase() ==
        proposedRule.pattern.trim().toLowerCase();
  }
}

class const _PreparedRule({
  required final CategorizationRule rule,
  required final String pattern,
  required final int patternLength,
});
