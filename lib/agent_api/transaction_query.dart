import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';

/// Filter shared by `/transactions`, `/transactions/totals`, `/merchants`,
/// and the `query` of `POST /transactions/notes`.
///
/// Every list parameter is comma-separated and matches any of its values.
/// `category` takes ids, `none` for uncategorized. `area` takes conscious
/// spending areas, `none` for spending whose category has none. `source` is
/// `rule`, `unruled`, or `none` (see [CategorizationSnapshot.categorySource]).
/// `search` and `note` are case-insensitive substrings (description or
/// merchant; note). Dates are `yyyy-mm-dd`, inclusive. Amount bounds compare
/// magnitude.
class const TransactionQuery({
  final Set<String>? transactionIds,
  final Set<String>? categoryIds,
  final Set<String>? areaNames,
  final String? source,
  final Set<String>? accountIds,
  final Set<AccountKind>? accountKinds,
  final String? ruleId,
  final String? search,
  final String? noteSearch,
  final bool? hasNote,
  final bool? excludedFromLifestyleCosts,
  final DateTime? since,
  final DateTime? until,

  /// Rows first written into the app at or after this instant (an import
  /// or bank pull), e.g. `2026-11-01T11:15`.
  final DateTime? importedSince,
  final int? minAmountCents,
  final int? maxAmountCents,
  final String? direction,
  final bool includeExcluded = true,
  final int limit = 200,
}) {
  static const uncategorizedCategoryId = 'none';
  static const noAreaName = 'none';

  /// Query-string parameters, or a JSON object's values as strings.
  factory fromQueryParameters(Map<String, String> parameters) {
    Set<String>? listOf(String key) {
      final value = parameters[key]?.trim();
      if (value == null || value.isEmpty) return null;
      return {
        for (final part in value.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      };
    }

    bool? flagOf(String key) => switch (parameters[key]) {
      null => null,
      'true' => true,
      'false' => false,
      final String other => throw ArgumentError(
        '"$key" must be true or false, not "$other".',
      ),
    };

    return TransactionQuery(
      transactionIds: listOf('ids'),
      categoryIds: listOf('category'),
      areaNames: listOf('area'),
      source: parameters['source'],
      accountIds: listOf('account'),
      accountKinds: listOf('accountKind')
          ?.map(AccountKind.values.byName)
          .toSet(),
      ruleId: parameters['rule'],
      search: parameters['search']?.trim().toLowerCase(),
      noteSearch: parameters['note']?.trim().toLowerCase(),
      hasNote: flagOf('hasNote'),
      excludedFromLifestyleCosts: flagOf('excludedFromLifestyleCosts'),
      since: parameters['since'] == null
          ? null
          : DateTime.parse(parameters['since']!),
      until: parameters['until'] == null
          ? null
          : DateTime.parse(parameters['until']!),
      importedSince: parameters['importedSince'] == null
          ? null
          : DateTime.parse(parameters['importedSince']!),
      minAmountCents: int.tryParse(parameters['minAmountCents'] ?? ''),
      maxAmountCents: int.tryParse(parameters['maxAmountCents'] ?? ''),
      direction: parameters['direction'],
      includeExcluded: parameters['includeExcluded'] != 'false',
      limit: int.tryParse(parameters['limit'] ?? '') ?? 200,
    );
  }

  /// A JSON body's filter object, same keys as the query string.
  factory fromJson(Map<String, dynamic> json) =>
      TransactionQuery.fromQueryParameters({
        for (final entry in json.entries)
          if (entry.value != null)
            entry.key: entry.value is List
                ? (entry.value as List).join(',')
                : '${entry.value}',
      });

  /// Whether anything narrows the match, so a bulk write never hits every
  /// transaction by accident.
  bool get narrows =>
      transactionIds != null ||
      categoryIds != null ||
      areaNames != null ||
      source != null ||
      accountIds != null ||
      accountKinds != null ||
      ruleId != null ||
      search != null ||
      noteSearch != null ||
      hasNote != null ||
      excludedFromLifestyleCosts != null ||
      since != null ||
      until != null ||
      importedSince != null ||
      minAmountCents != null ||
      maxAmountCents != null ||
      direction != null;

  /// Newest first.
  List<BankTransaction> matchingTransactions(CategorizationSnapshot snapshot) {
    return [
      for (final transaction in snapshot.transactions)
        if (_matches(transaction, snapshot)) transaction,
    ]..sort(
      (left, right) => right.postedAtMillis.compareTo(left.postedAtMillis),
    );
  }

  bool _matches(BankTransaction transaction, CategorizationSnapshot snapshot) {
    if (transactionIds != null && !transactionIds!.contains(transaction.id)) {
      return false;
    }
    if (!includeExcluded && transaction.excluded) return false;
    if (accountIds != null && !accountIds!.contains(transaction.accountId)) {
      return false;
    }
    if (accountKinds != null &&
        !accountKinds!.contains(
          snapshot.accountsById[transaction.accountId]?.kind,
        )) {
      return false;
    }
    if (categoryIds != null &&
        !categoryIds!.contains(
          transaction.categoryId ?? uncategorizedCategoryId,
        )) {
      return false;
    }
    if (areaNames != null &&
        !areaNames!.contains(
          snapshot
                  .categoriesById[transaction.categoryId]
                  ?.consciousSpendingArea
                  ?.name ??
              noAreaName,
        )) {
      return false;
    }
    if (ruleId != null && transaction.categoryRuleId != ruleId) return false;
    if (excludedFromLifestyleCosts != null &&
        transaction.excludedFromLifestyleCosts != excludedFromLifestyleCosts) {
      return false;
    }
    final String note = transaction.note?.trim().toLowerCase() ?? '';
    if (hasNote != null && note.isNotEmpty != hasNote) return false;
    if (noteSearch != null && !note.contains(noteSearch!)) return false;
    if (maxAmountCents != null &&
        transaction.amountCents.abs() > maxAmountCents!) {
      return false;
    }
    if (importedSince != null &&
        (transaction.importedAtMillis ?? 0) <
            importedSince!.millisecondsSinceEpoch) {
      return false;
    }
    if (since != null &&
        transaction.postedAtMillis < since!.millisecondsSinceEpoch) {
      return false;
    }
    if (until != null &&
        transaction.postedAtMillis >
            until!.add(const Duration(days: 1)).millisecondsSinceEpoch) {
      return false;
    }
    if (minAmountCents != null &&
        transaction.amountCents.abs() < minAmountCents!) {
      return false;
    }
    if (direction == 'inflow' && !transaction.isInflow) return false;
    if (direction == 'outflow' && !transaction.isOutflow) return false;
    if (search != null &&
        !transaction.rawDescription.toLowerCase().contains(search!) &&
        !transaction.normalizedMerchant.toLowerCase().contains(search!)) {
      return false;
    }
    if (source != null && snapshot.categorySource(transaction) != source) {
      return false;
    }
    return true;
  }
}
