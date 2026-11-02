import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/accounts/account.dart';

class BankTransaction({
  required final String id,
  required final String accountId,
  required final String externalId,

  /// Epoch milliseconds of the posting instant, as the bank reports it and
  /// the table stores it. [postedDay] is derived once; building a local
  /// [DateTime] costs microseconds, so nothing here holds one.
  required final int postedAtMillis,
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

  /// Copilot's exclude-from-totals flag at import, kept only as provenance
  /// (Activity shows it). Totals follow the category, which comes from
  /// rules; the flag never overrides one.
  final bool excluded = false,
  final String? recurringSeries,

  /// Set only with [categoryId], from its rule's [CategorizationRule.excludesFromLifestyleCosts].
  final bool excludedFromLifestyleCosts = false,

  /// Epoch milliseconds when first written into Budgets (import or sync).
  /// Stable across re-upserts.
  final int? importedAtMillis,
}) {
  /// Transactions before this date are incomplete enough to distort trends.
  static final completeHistoryStart = DateTime(2021, 3, 1);

  /// The local calendar day the transaction posted on.
  final CalendarDay postedDay = CalendarDay.fromLocalMillis(postedAtMillis);

  bool get isUncategorized => categoryId == null;

  /// From a Copilot CSV export, which can list one charge twice under
  /// different ids. The live bank feed and Empower each report a
  /// transaction once under a stable id.
  bool get isCopilotImport => externalId.startsWith('copilot:');

  /// From an Empower history import (`empower:<id>`), which can record the
  /// same contribution the live bank feed later reports.
  bool get isEmpowerImport => externalId.startsWith('empower:');

  bool get isOutflow => amountCents < 0;
  bool get isInflow => amountCents > 0;
  bool get isZeroAmount => amountCents == 0;

  /// Copilot accounts with belongs-to are enrichment only — parent rows win.
  bool isLinkedCopilotEnrichment(Map<String, Account> accounts) {
    final account = accounts[accountId];
    return account != null && account.isCopilot && account.hasParent;
  }
}
