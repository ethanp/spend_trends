import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

/// Stable colors for category identity across Activity / Trends.
///
/// Grouped categories share a hue from [SpendCategory.groupId], with a
/// per-category shade so members stay related but distinct. Ungrouped
/// categories keep a per-category palette color. Built-ins stay pinned.
class CategoryColor._() {
  static const uncategorized = EColors.textMuted;
  static const housing = FinanceColors.housing;
  static const income = EColors.success;
  static const transfer = FinanceColors.accentSecondary;
  static const assetSale = Color(0xFFF77F00);

  /// Same palette as Trends series (readable on dark surfaces).
  static const palette = <Color>[
    Color(0xFF4CC9F0),
    Color(0xFFF4A261),
    Color(0xFFB5179E),
    Color(0xFF80ED99),
    Color(0xFFFFD166),
    Color(0xFF4361EE),
    Color(0xFFFF6B35),
    Color(0xFF9B5DE5),
    Color(0xFF2EC4B6),
    Color(0xFFF72585),
  ];

  static Color forCategoryId(
    String? categoryId, {
    String? categoryName,
    String? groupId,
  }) {
    if (SpecialCategory.isHousingId(categoryId) ||
        SpecialCategory.isHousingName(categoryName)) {
      return housing;
    }
    if (categoryId == null || categoryId.isEmpty) return uncategorized;
    if (SpecialCategory.isIncomeId(categoryId) ||
        SpecialCategory.isInvestmentsName(categoryName)) {
      return income;
    }
    if (SpecialCategory.isTransferId(categoryId)) return transfer;
    if (SpecialCategory.isAssetSaleId(categoryId)) return assetSale;
    final trimmedGroupId = groupId?.trim();
    if (trimmedGroupId != null && trimmedGroupId.isNotEmpty) {
      return forGroupId(trimmedGroupId).shadeKeyedBy(categoryId);
    }
    return palette[categoryId.stableHash % palette.length];
  }

  static Color forCategory(SpendCategory category) => forCategoryId(
    category.id,
    categoryName: category.name,
    groupId: category.groupId,
  );

  static Color forGroupId(String groupId) =>
      palette[groupId.stableHash % palette.length];
}
