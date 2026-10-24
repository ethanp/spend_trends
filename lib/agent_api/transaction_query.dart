import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/domain/transaction.dart';

/// Query-string filter for `/transactions` and `/merchants`.
///
/// `category=none` selects uncategorized rows. `source` is one of `user`,
/// `rule`, `import`, `none` (see [CategorizationSnapshot.transactionJson]).
/// `search` is a case-insensitive substring of description or merchant.
/// Dates are `yyyy-mm-dd`, inclusive. `minAmountCents` compares magnitude.
class const TransactionQuery({
  final String? categoryId,
  final String? source,
  final String? accountId,
  final String? search,
  final DateTime? since,
  final DateTime? until,
  final int? minAmountCents,
  final String? direction,
  final bool includeExcluded = true,
  final int limit = 200,
}) {
  static const uncategorizedCategoryId = 'none';

  factory fromQueryParameters(Map<String, String> parameters) {
    return TransactionQuery(
      categoryId: parameters['category'],
      source: parameters['source'],
      accountId: parameters['account'],
      search: parameters['search']?.trim().toLowerCase(),
      since: parameters['since'] == null
          ? null
          : DateTime.parse(parameters['since']!),
      until: parameters['until'] == null
          ? null
          : DateTime.parse(parameters['until']!),
      minAmountCents: int.tryParse(parameters['minAmountCents'] ?? ''),
      direction: parameters['direction'],
      includeExcluded: parameters['includeExcluded'] != 'false',
      limit: int.tryParse(parameters['limit'] ?? '') ?? 200,
    );
  }

  /// Newest first.
  List<BankTransaction> matchingTransactions(CategorizationSnapshot snapshot) {
    return [
      for (final transaction in snapshot.transactions)
        if (_matches(transaction, snapshot)) transaction,
    ]..sort((left, right) => right.postedAt.compareTo(left.postedAt));
  }

  bool _matches(BankTransaction transaction, CategorizationSnapshot snapshot) {
    if (!includeExcluded && transaction.excluded) return false;
    if (accountId != null && transaction.accountId != accountId) return false;
    if (categoryId != null) {
      if (categoryId == uncategorizedCategoryId) {
        if (!transaction.isUncategorized) return false;
      } else if (transaction.categoryId != categoryId) {
        return false;
      }
    }
    if (since != null && transaction.postedAt.isBefore(since!)) return false;
    if (until != null &&
        transaction.postedAt.isAfter(until!.add(const Duration(days: 1)))) {
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
