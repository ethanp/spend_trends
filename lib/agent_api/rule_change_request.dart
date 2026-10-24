import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/rule_change_plan.dart';

/// Rule upserts and deletions from a request body, validated against the
/// current categories and accounts.
///
/// Body: one rule object, or `{"rules": [...], "deleteRuleIds": [...]}`. A
/// rule object is `{pattern, categoryId, matchType?, accountId?, note?}`;
/// `matchType` is `contains` (default), `exact`, or `account` (every
/// transaction on accountId; pattern omitted).
class const RuleChangeRequest({
  required final List<RuleDraft> drafts,
  required final Set<String> deletedRuleIds,
}) {
  factory fromBody(Map<String, dynamic> body, CategorizationSnapshot snapshot) {
    final ruleObjects = body.containsKey('rules')
        ? [
            for (final rule in body['rules'] as List)
              rule as Map<String, dynamic>,
          ]
        : body.containsKey('categoryId')
        ? [body]
        : const <Map<String, dynamic>>[];
    final deletedRuleIds = {
      for (final ruleId in (body['deleteRuleIds'] as List?) ?? const [])
        ruleId as String,
    };
    for (final ruleId in deletedRuleIds) {
      if (!snapshot.rulesById.containsKey(ruleId)) {
        throw ArgumentError('No rule $ruleId.');
      }
    }
    return RuleChangeRequest(
      drafts: [for (final rule in ruleObjects) _draftFrom(rule, snapshot)],
      deletedRuleIds: deletedRuleIds,
    );
  }

  static RuleDraft _draftFrom(
    Map<String, dynamic> rule,
    CategorizationSnapshot snapshot,
  ) {
    final categoryId = rule.requiredString('categoryId');
    if (!snapshot.categoriesById.containsKey(categoryId)) {
      throw ArgumentError('No category $categoryId.');
    }
    final accountId = rule['accountId'] as String?;
    if (accountId != null && !snapshot.accountsById.containsKey(accountId)) {
      throw ArgumentError('No account $accountId.');
    }
    final RuleMatchType matchType = switch (rule['matchType'] as String?) {
      null || 'contains' => RuleMatchType.merchantContains,
      'exact' => RuleMatchType.merchantExact,
      'account' => RuleMatchType.wholeAccount,
      final String other => throw ArgumentError(
        'matchType must be "contains", "exact", or "account", not "$other".',
      ),
    };
    return RuleDraft(
      pattern: matchType.usesPattern ? rule.requiredString('pattern') : '',
      categoryId: categoryId,
      matchType: matchType,
      accountId: accountId,
      note: rule['note'] as String?,
    );
  }
}

/// JSON report of what a [RuleChangePlan] does: each rule and how many
/// transactions it takes, then every category change grouped by
/// from → to with samples, so collateral moves are visible before applying.
class const RuleChangeReport({
  required final RuleChangePlan plan,
  required final CategorizationSnapshot snapshot,
  final bool includeAllTransactions = false,
}) {
  static const samplesPerChange = 5;

  Map<String, Object?> toJson() {
    final ruleIdsBefore = {for (final rule in plan.rulesBefore) rule.id};
    final takenCountByRuleId = <String, int>{};
    for (final move in plan.recategorized) {
      final ruleId = move.rule?.id;
      if (ruleId == null) continue;
      takenCountByRuleId.update(
        ruleId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return {
      'rules': [
        for (final rule in plan.upserts)
          {
            'id': rule.id,
            'isNew': !ruleIdsBefore.contains(rule.id),
            'pattern': rule.pattern,
            'matchType': rule.matchType.storageValue,
            'accountId': rule.accountId,
            'category': snapshot.categoriesById[rule.categoryId]?.name,
            'note': rule.note,
            'takes': takenCountByRuleId[rule.id] ?? 0,
          },
      ],
      'deletedRuleIds': plan.deletedRuleIds.toList(),
      'transactionsMoved': plan.recategorized.length,
      'categoryChanges': plan.categoryChanges.length,
      'byCategoryChange': _byCategoryChange(),
      if (includeAllTransactions)
        'transactions': [
          for (final move in plan.recategorized)
            {
              ...snapshot.transactionJson(move.transaction),
              'newCategory': snapshot.categoriesById[move.categoryId]?.name,
              'newRuleId': move.rule?.id,
            },
        ],
    };
  }

  List<Map<String, Object?>> _byCategoryChange() {
    final movesByChange = <String, List<RecategorizedTransaction>>{};
    for (final move in plan.categoryChanges) {
      movesByChange
          .putIfAbsent(
            '${move.transaction.categoryId}→${move.categoryId}',
            () => [],
          )
          .add(move);
    }
    final changes = [
      for (final moves in movesByChange.values)
        {
          'from':
              snapshot.categoriesById[moves.first.transaction.categoryId]?.name,
          'to': snapshot.categoriesById[moves.first.categoryId]?.name,
          'count': moves.length,
          'samples': [
            for (final move in moves.take(samplesPerChange))
              {
                'id': move.transaction.id,
                'postedOn': move.transaction.postedAt.dayKey,
                'amount': formatCents(move.transaction.amountCents),
                'description': move.transaction.rawDescription,
                'rulePattern': move.rule?.pattern,
              },
          ],
        },
    ];
    changes.sort(
      (left, right) => (right['count'] as int).compareTo(left['count'] as int),
    );
    return changes;
  }
}
