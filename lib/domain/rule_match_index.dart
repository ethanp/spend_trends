import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';

/// Pre-normalized rules for repeated matching without re-trimming patterns.
///
/// When several rules match a transaction, the most specific wins: one
/// account over all accounts, then exact over contains over whole-account,
/// then the longer pattern. Ties break alphabetically so the winner is
/// stable.
class RuleMatchIndex(List<CategorizationRule> rules) {
  final List<_PreparedRule> _preparedRules = [
    for (final rule in rules)
      if (rule.pattern.trim().isNotEmpty || !rule.matchType.usesPattern)
        _PreparedRule(rule: rule, pattern: rule.pattern.trim().toLowerCase()),
  ];

  late final Map<String, CategorizationRule> rulesById = {
    for (final prepared in _preparedRules) prepared.rule.id: prepared.rule,
  };

  CategorizationRule? bestMatchingRule(BankTransaction transaction) {
    final searchText = _MatchText(transaction);
    _PreparedRule? best;
    for (final prepared in _preparedRules) {
      if (!prepared.matches(transaction, searchText)) continue;
      if (best == null || prepared.isMoreSpecificThan(best)) best = prepared;
    }
    return best?.rule;
  }

  /// Case-insensitive match of [rule] against the transaction description.
  static bool ruleMatches(
    BankTransaction transaction,
    CategorizationRule rule,
  ) {
    final pattern = rule.pattern.trim().toLowerCase();
    if (pattern.isEmpty && rule.matchType.usesPattern) return false;
    return _PreparedRule(
      rule: rule,
      pattern: pattern,
    ).matches(transaction, _MatchText(transaction));
  }
}

class _MatchText(BankTransaction transaction) {
  final String merchant = transaction.normalizedMerchant.toLowerCase();
  final String description = transaction.rawDescription.trim().toLowerCase();
  late final String descriptionAndMerchant = '$description\n$merchant';
}

class const _PreparedRule({
  required final CategorizationRule rule,
  required final String pattern,
}) {
  bool matches(BankTransaction transaction, _MatchText searchText) {
    if (!rule.appliesToTransaction(transaction)) return false;
    return switch (rule.matchType) {
      RuleMatchType.wholeAccount => rule.isLimitedToOneAccount,
      RuleMatchType.merchantExact =>
        searchText.merchant == pattern || searchText.description == pattern,
      RuleMatchType.merchantContains =>
        searchText.descriptionAndMerchant.contains(pattern),
    };
  }

  bool isMoreSpecificThan(_PreparedRule incumbent) {
    if (rule.isLimitedToOneAccount != incumbent.rule.isLimitedToOneAccount) {
      return rule.isLimitedToOneAccount;
    }
    if (rule.matchType != incumbent.rule.matchType) {
      return rule.matchType.specificity > incumbent.rule.matchType.specificity;
    }
    if (pattern.length != incumbent.pattern.length) {
      return pattern.length > incumbent.pattern.length;
    }
    return pattern.compareTo(incumbent.pattern) < 0;
  }
}
