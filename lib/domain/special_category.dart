import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';

/// Built-in categories with stable ids.
///
/// [income] is take-home pay. [investments] holds 401(k)-style contributions
/// that fill the Investments area of the conscious spending plan.
/// [transfer] and [assetSale] are excluded from spend and income totals and
/// stay ungrouped. [assetSale] is a one-time lump sum (house sale, payoff
/// at closing) that net worth plots apart from saving.
/// [housing] is a built-in spend category (kept in spend Trends / month rows)
/// so its color and future housing-specific behavior stay consistent.
enum SpecialCategory({
  required final String id,
  required final String name,
  required final int sortOrder,
  final bool countsAsIncome = false,
  final bool excludedFromSpend = false,
  final String? defaultGroupId,
  final ConsciousSpendingArea? defaultConsciousSpendingArea,

  /// Editor explanation for a built-in that cannot be renamed or deleted.
  final String? lockedCaption,
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
    excludedFromSpend: true,
    defaultGroupId: 'grp_income',
    lockedCaption:
        'Income · excluded from spend trends. '
        'It cannot be renamed or deleted.',
  ),
  transfer(
    id: 'cat_transfer',
    name: 'Transfer',
    sortOrder: 1001,
    excludedFromSpend: true,
    lockedCaption:
        'Transfer · excluded from spend trends. '
        'It cannot be renamed or deleted. '
        'Use it for money moving between your own accounts.',
  ),
  investments(
    id: 'cat_investments',
    name: 'Investments',
    sortOrder: 1002,
    excludedFromSpend: true,
    defaultGroupId: 'grp_income',
  ),
  assetSale(
    id: 'cat_asset_sale',
    name: 'Asset sale',
    sortOrder: 1003,
    excludedFromSpend: true,
    lockedCaption:
        'Asset sale · excluded from spend and income. '
        'It cannot be renamed or deleted. '
        'Use it for one-time proceeds like a house sale; '
        'net worth shows them as lump sums.',
  );

  static const incomeGroupId = 'grp_income';
  static const incomeGroupName = 'Income';
  static const incomeGroupSortOrder = 2;

  static final ids = {for (final special in values) special.id};

  /// Income + Investments + Transfer + Asset sale — excluded from spend
  /// series and month rows.
  static final flowIds = {
    for (final special in values)
      if (special.excludedFromSpend) special.id,
  };

  static final lockedIds = {
    for (final special in values)
      if (special.lockedCaption != null) special.id,
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

  static SpecialCategory? fromId(String? categoryId) {
    for (final special in values) {
      if (special.id == categoryId) return special;
    }
    return null;
  }

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

  static bool isAssetSaleId(String? categoryId) => categoryId == assetSale.id;

  static bool isInvestmentsId(String? categoryId) =>
      categoryId == investments.id;

  static bool isIncomeGroupId(String? groupId) => groupId == incomeGroupId;

  static bool isReservedName(String name) => idForReservedName(name) != null;

  static String? idForReservedName(String name) =>
      _idsByNormalizedName[CategoryName(name).normalized];

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

  bool get isFlow => SpecialCategory.isFlowId(id) || isInvestments;

  bool get isIncome => SpecialCategory.isIncomeId(id);

  bool get isInvestments =>
      SpecialCategory.isInvestmentsId(id) ||
      SpecialCategory.isInvestmentsName(name);

  bool get isTransfer => SpecialCategory.isTransferId(id);

  bool get isAssetSale => SpecialCategory.isAssetSaleId(id);

  /// Non-null for built-ins that cannot be renamed or deleted.
  String? get lockedCaption => SpecialCategory.fromId(id)?.lockedCaption;

  String? get builtInCaption {
    if (isIncome) return 'Built-in · income';
    if (isInvestments) return 'Built-in · investments';
    if (isTransfer) return 'Built-in · transfer';
    if (isAssetSale) return 'Built-in · asset sale';
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
