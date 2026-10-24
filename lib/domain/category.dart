import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/transaction.dart';

/// Category display name with case/whitespace-insensitive identity.
class const CategoryName(final String value) {
  String get normalized => value.trim().toLowerCase();

  bool matches(CategoryName other) => normalized == other.normalized;

  @override
  bool operator ==(Object other) =>
      other is CategoryName && normalized == other.normalized;

  @override
  int get hashCode => normalized.hashCode;

  @override
  String toString() => value;
}

class const SpendCategory({
  required final String id,
  required final String name,
  required final int sortOrder,
  required final bool archived,
  final String? colorToken,
  final String? groupId,
  final ConsciousSpendingArea? consciousSpendingArea,
}) {
  SpendCategory copyWith({
    String? name,
    int? sortOrder,
    bool? archived,
    String? colorToken,
    String? groupId,
    bool clearGroupId = false,
    ConsciousSpendingArea? consciousSpendingArea,
    bool clearConsciousSpendingArea = false,
  }) {
    return SpendCategory(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
      colorToken: colorToken ?? this.colorToken,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      consciousSpendingArea: clearConsciousSpendingArea
          ? null
          : (consciousSpendingArea ?? this.consciousSpendingArea),
    );
  }
}

class const CategorizationRule({
  required final String id,
  required final RuleMatchType matchType,
  required final String pattern,
  required final String categoryId,
  required final int priority,
  final String? accountId,
}) {
  /// Weakest priority — Copilot / import defaults lose to user-created rules.
  static const defaultImportPriority = 0;

  /// Priority for rules created from the Activity recategorize sheet.
  static const userCreatedPriority = 10;

  bool get isDefaultImport => priority == defaultImportPriority;

  bool get beatsImportDefault => priority > defaultImportPriority;

  bool get isLimitedToOneAccount => accountId != null;

  bool appliesToTransaction(BankTransaction transaction) =>
      accountId == null || accountId == transaction.accountId;

  String accountScopeLabel(Map<String, Account> accountsById) {
    if (accountId == null) return 'All accounts';
    final account = accountsById[accountId!];
    if (account == null) return 'One account';
    return account.displayNameWithInstitution;
  }
}

enum RuleMatchType() {
  merchantContains,
  merchantExact;

  static RuleMatchType fromStorage(String value) {
    return RuleMatchType.values.firstWhere(
      (matchType) => matchType.name == value,
      orElse: () => RuleMatchType.merchantContains,
    );
  }

  String get storageValue => name;
}
