import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/rule_match_index.dart';
import 'package:spend_trends/domain/transaction.dart';

/// A rule to add or change. It updates the rule with the same match type,
/// pattern, and account when one exists, so re-adding a pattern retargets it.
class const RuleDraft({
  required final String pattern,
  required final String categoryId,
  final RuleMatchType matchType = RuleMatchType.merchantContains,
  final String? accountId,

  /// Kept from the existing rule when null.
  final String? note,
}) {
  /// The same rule pointed at [categoryId], optionally with a new [note].
  factory retargeting(
    CategorizationRule rule, {
    required String categoryId,
    String? note,
  }) => RuleDraft(
    pattern: rule.pattern,
    categoryId: categoryId,
    matchType: rule.matchType,
    accountId: rule.accountId,
    note: note,
  );

  String get normalizedPattern => pattern.trim().toLowerCase();

  bool sameMatchAs(CategorizationRule rule) =>
      rule.matchType == matchType &&
      rule.accountId == accountId &&
      rule.pattern.trim().toLowerCase() == normalizedPattern;

  CategorizationRule asRule({required String id, String? fallbackNote}) =>
      CategorizationRule(
        id: id,
        matchType: matchType,
        pattern: normalizedPattern,
        categoryId: categoryId,
        accountId: accountId,
        note: note ?? fallbackNote,
      );

  bool matches(BankTransaction transaction) =>
      RuleMatchIndex.ruleMatches(transaction, asRule(id: 'draft'));
}

/// One transaction whose category or categorizing rule a change moves.
class const RecategorizedTransaction({
  required final BankTransaction transaction,
  required final CategorizationRule? rule,
}) {
  String? get categoryId => rule?.categoryId;

  bool get changesCategory => categoryId != transaction.categoryId;
}

/// What upserting and deleting rules does to every transaction, worked out
/// before anything is written.
///
/// Only transactions that match a changed rule, or that a changed or deleted
/// rule categorized, are reconsidered, unless [reconsiderAll] (used after new
/// transactions arrive).
class RuleChangePlan({
  required final List<CategorizationRule> rulesBefore,
  required final List<BankTransaction> transactions,
  final List<CategorizationRule> upserts = const [],
  final Set<String> deletedRuleIds = const {},
  final bool reconsiderAll = false,
}) {
  late final List<CategorizationRule> rulesAfter = [
    for (final rule in rulesBefore)
      if (!deletedRuleIds.contains(rule.id) && !_upsertIds.contains(rule.id))
        rule,
    ...upserts,
  ];

  late final List<RecategorizedTransaction> recategorized = () {
    final ruleMatchIndex = RuleMatchIndex(rulesAfter);
    return [
      for (final transaction in transactions)
        if (reconsiderAll || _mayMove(transaction))
          RecategorizedTransaction(
            transaction: transaction,
            rule: ruleMatchIndex.bestMatchingRule(transaction),
          ),
    ].where(_isMove).toList();
  }();

  /// Category changes only (a different rule picking the same category is
  /// still written, so provenance stays accurate, but is not a move).
  List<RecategorizedTransaction> get categoryChanges => [
    for (final move in recategorized)
      if (move.changesCategory) move,
  ];

  late final Set<String> _upsertIds = {for (final rule in upserts) rule.id};

  late final Set<String> _changedRuleIds = {..._upsertIds, ...deletedRuleIds};

  bool _mayMove(BankTransaction transaction) {
    if (_changedRuleIds.contains(transaction.categoryRuleId)) return true;
    for (final rule in upserts) {
      if (RuleMatchIndex.ruleMatches(transaction, rule)) return true;
    }
    return false;
  }

  static bool _isMove(RecategorizedTransaction move) =>
      move.rule?.id != move.transaction.categoryRuleId || move.changesCategory;
}
