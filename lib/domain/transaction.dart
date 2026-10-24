import 'package:spend_trends/domain/account.dart';

class const BankTransaction({
  required final String id,
  required final String accountId,
  required final String externalId,
  required final DateTime postedAt,
  required final int amountCents,
  required final String rawDescription,
  required final String normalizedMerchant,
  required final bool pending,

  /// Set only by the categorization rule in [categoryRuleId]; null when no
  /// rule matches.
  final String? categoryId,
  final String? categoryRuleId,
  final String? note,
  final String? transactionType,
  final bool excluded = false,
  final String? recurringSeries,

  /// When first written into Budgets (import or sync). Stable across re-upserts.
  final DateTime? importedAt,
}) {
  bool get isUncategorized => categoryId == null;

  bool get isOutflow => amountCents < 0;
  bool get isInflow => amountCents > 0;
  bool get isZeroAmount => amountCents == 0;

  /// Copilot accounts with belongs-to are enrichment only — parent rows win.
  bool isLinkedCopilotEnrichment(Map<String, Account> accounts) {
    final account = accounts[accountId];
    return account != null && account.isCopilot && account.hasParent;
  }
}
