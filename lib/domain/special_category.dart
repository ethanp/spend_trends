import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';

/// Built-in categories with stable ids.
///
/// [income] / [investments] count as income (excluded from spend totals).
/// [transfer] is excluded from spend totals and stays ungrouped.
/// [housing] is a built-in spend category (kept in spend Trends / month rows)
/// so its color and future housing-specific behavior stay consistent.
enum SpecialCategory({
  required final String id,
  required final String name,
  required final int sortOrder,
  final bool countsAsIncome = false,
  final String? defaultGroupId,
  final ConsciousSpendingArea? defaultConsciousSpendingArea,
}) {
  housing(
    id: 'cat_housing',
    name: 'Housing',
    sortOrder: 3,
    defaultConsciousSpendingArea: ConsciousSpendingArea.fixedCosts,
  ),
  income(
    id: 'cat_income',
    name: 'Income',
    sortOrder: 1000,
    countsAsIncome: true,
    defaultGroupId: 'grp_income',
  ),
  transfer(id: 'cat_transfer', name: 'Transfer', sortOrder: 1001),
  investments(
    id: 'cat_investments',
    name: 'Investments',
    sortOrder: 1002,
    countsAsIncome: true,
    defaultGroupId: 'grp_income',
  );

  static const incomeGroupId = 'grp_income';
  static const incomeGroupName = 'Income';
  static const incomeGroupSortOrder = 2;

  static final ids = {for (final special in values) special.id};

  /// Income + Investments + Transfer — excluded from spend series and month rows.
  static final flowIds = {
    for (final special in values)
      if (special.countsAsIncome || special == transfer) special.id,
  };

  static final incomeIds = {
    for (final special in values)
      if (special.countsAsIncome) special.id,
  };

  static final _idsByNormalizedName = {
    for (final special in values)
      CategoryName(special.name).normalized: special.id,
  };

  static final housingName = CategoryName(housing.name);
  static final investmentsName = CategoryName(investments.name);

  static CategoryGroup get incomeGroup => const CategoryGroup(
    id: incomeGroupId,
    name: incomeGroupName,
    sortOrder: incomeGroupSortOrder,
  );

  static bool isSpecialId(String? categoryId) =>
      categoryId != null && ids.contains(categoryId);

  static bool isFlowId(String? categoryId) =>
      categoryId != null && flowIds.contains(categoryId);

  static bool isHousingId(String? categoryId) => categoryId == housing.id;

  static bool isHousingName(String? name) =>
      name != null && CategoryName(name).matches(housingName);

  static bool isIncomeId(String? categoryId) =>
      categoryId != null && incomeIds.contains(categoryId);

  static bool isInvestmentsName(String? name) =>
      name != null && CategoryName(name).matches(investmentsName);

  static bool isTransferId(String? categoryId) => categoryId == transfer.id;

  static bool isIncomeGroupId(String? groupId) => groupId == incomeGroupId;

  static bool isReservedName(String name) => idForReservedName(name) != null;

  static String? idForReservedName(String name) =>
      _idsByNormalizedName[CategoryName(name).normalized];

  /// Maps Copilot / legacy `transaction_type` values onto a cash-flow category.
  static SpecialCategory? fromTransactionType(String? transactionType) {
    final type = transactionType?.trim().toLowerCase() ?? '';
    if (type == 'income') return income;
    if (type == 'transfer' || type == 'internal transfer') return transfer;
    return null;
  }

  SpendCategory asSpendCategory({bool archived = false}) => SpendCategory(
    id: id,
    name: name,
    sortOrder: sortOrder,
    archived: archived,
    groupId: defaultGroupId,
    consciousSpendingArea: defaultConsciousSpendingArea,
  );
}

extension SpendCategorySpecial on SpendCategory {
  bool get isHousing =>
      SpecialCategory.isHousingId(id) || SpecialCategory.isHousingName(name);

  bool get isFlow => SpecialCategory.isFlowId(id) || isIncome || isTransfer;

  bool get isIncome =>
      SpecialCategory.isIncomeId(id) || SpecialCategory.isInvestmentsName(name);

  bool get isTransfer => SpecialCategory.isTransferId(id);

  String? get builtInCaption {
    if (isIncome) return 'Built-in · income';
    if (isTransfer) return 'Built-in · transfer';
    if (isHousing) return 'Built-in · housing';
    return null;
  }

  /// Built-in catch bucket (`cat_other` or display name "Other").
  bool get isOther =>
      id == 'cat_other' || CategoryName(name).normalized == 'other';

  /// Broad catch-all names the LLM must not treat as real categories.
  bool get isCatchAll => id == 'cat_other' || CategoryName(name).isCatchAll;
}

extension CategoryNameCatchAll on CategoryName {
  bool get isCatchAll {
    return normalized == 'other' ||
        normalized == 'misc' ||
        normalized == 'miscellaneous' ||
        normalized == 'uncategorized' ||
        normalized == 'general';
  }
}
