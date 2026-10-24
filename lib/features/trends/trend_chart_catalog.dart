import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/theme/finance_colors.dart';

/// Series ids, colors, and shared Trends chart constants.
class TrendChartCatalog._() {
  static const allSpendSeriesId = '__all__';
  static const uncategorizedSeriesId = '__uncategorized__';
  static const incomeSeriesId = '__income__';
  static const spendingSeriesId = '__spending__';
  static const transferSeriesId = '__transfer__';
  static const savingsSeriesId = '__savings__';
  static const netWorthSeriesId = '__net_worth__';
  static const housingAffordabilitySeriesId = '__housing_30__';
  static const fireSavingsGuideSeriesId = '__savings_25__';
  static const groupSeriesIdPrefix = 'group:';
  static const consciousSpendingAreaSeriesIdPrefix = 'area:';
  static const accountSeriesIdPrefix = 'account:';
  static const ownedAssetSeriesIdPrefix = 'owned_asset:';

  static String groupSeriesId(String groupId) => '$groupSeriesIdPrefix$groupId';

  static String consciousSpendingAreaSeriesId(ConsciousSpendingArea area) =>
      '$consciousSpendingAreaSeriesIdPrefix${area.name}';

  static String accountSeriesId(String accountId) =>
      '$accountSeriesIdPrefix$accountId';

  static String ownedAssetSeriesId(String ownedAssetId) =>
      '$ownedAssetSeriesIdPrefix$ownedAssetId';

  /// Housing ≤ this share of income (bank income ≈ net).
  static const housingIncomeShareCap = 0.30;

  /// FIRE rule of thumb: save at least this share of income.
  static const fireSavingsIncomeShare = 0.25;

  /// History before this date is incomplete enough to distort trends.
  static final chartHistoryStart = DateTime(2021, 3, 1);

  static const allSpendLineColor = Color(0xFF8B1E2D);
  static const uncategorizedLineColor = Color(0xFF9AA0A6);
  static const incomeLineColor = Color(0xFF3FB37F);
  static const spendingLineColor = FinanceColors.housing;
  static const transferLineColor = Color(0xFF7B8CDE);
  static const savingsLineColor = Color(0xFF56CCF2);
  static const netWorthLineColor = Color(0xFFE9C46A);

  static final housingAffordabilityLineColor = Color.lerp(
    FinanceColors.housing,
    const Color(0xFFE53935),
    0.3,
  )!;

  static final fireSavingsGuideLineColor = Color.lerp(
    savingsLineColor,
    EColors.success,
    0.45,
  )!;
}
