import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';

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
  final ConsciousSpendingArea? consciousSpendingArea,
}) {
  SpendCategory copyWith({
    String? name,
    int? sortOrder,
    bool? archived,
    String? colorToken,
    ConsciousSpendingArea? consciousSpendingArea,
    bool clearConsciousSpendingArea = false,
  }) {
    return SpendCategory(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
      colorToken: colorToken ?? this.colorToken,
      consciousSpendingArea: clearConsciousSpendingArea
          ? null
          : (consciousSpendingArea ?? this.consciousSpendingArea),
    );
  }
}

/// The only way a transaction gets a category. When several rules match, the
/// most specific wins (see [RuleMatchIndex]).
class const CategorizationRule({
  required final String id,
  required final RuleMatchType matchType,
  required final String pattern,
  required final String categoryId,
  final String? accountId,

  /// Why this rule exists and any assumptions behind it.
  final String? note,

  /// What this rule categorizes is left out of lifestyle costs (a home
  /// overlap, a closing): it keeps its category but fills no conscious
  /// spending area and stays out of the FIRE projection's baseline.
  final bool excludesFromLifestyleCosts = false,
}) {
  bool get isLimitedToOneAccount => accountId != null;

  /// e.g. `contains “kroger”`, `exact “amazon”`, `every transaction`.
  String get matchCaption => switch (matchType) {
    RuleMatchType.merchantContains => 'contains “$pattern”',
    RuleMatchType.merchantExact => 'exact “$pattern”',
    RuleMatchType.wholeAccount => 'every transaction',
  };

  bool appliesToTransaction(BankTransaction transaction) =>
      accountId == null || accountId == transaction.accountId;

  String accountScopeLabel(Map<String, Account> accountsById) {
    if (accountId == null) return 'All accounts';
    final account = accountsById[accountId!];
    if (account == null) return 'One account';
    return account.displayNameWithInstitution;
  }

  CategorizationRule copyWith({
    String? categoryId,
    String? note,
    bool? excludesFromLifestyleCosts,
  }) => CategorizationRule(
    id: id,
    matchType: matchType,
    pattern: pattern,
    categoryId: categoryId ?? this.categoryId,
    accountId: accountId,
    note: note ?? this.note,
    excludesFromLifestyleCosts:
        excludesFromLifestyleCosts ?? this.excludesFromLifestyleCosts,
  );
}

enum RuleMatchType({required final int specificity}) {
  /// Every transaction on the rule's account (feeds with blank descriptions,
  /// e.g. staking rewards). Needs an account; the pattern is empty.
  wholeAccount(specificity: 0),
  merchantContains(specificity: 1),
  merchantExact(specificity: 2);

  bool get usesPattern => this != wholeAccount;

  static RuleMatchType fromStorage(String value) {
    return RuleMatchType.values.firstWhere(
      (matchType) => matchType.name == value,
      orElse: () => RuleMatchType.merchantContains,
    );
  }

  String get storageValue => name;
}
