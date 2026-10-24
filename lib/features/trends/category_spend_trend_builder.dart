import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/annual_pace_smoother.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/util/category_color.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

/// Daily spend totals keyed by category (and rollups).
class const CategorySpendDailyMaps({
  required final Map<String, Map<DateTime, double>> byCategoryId,
  required final Map<DateTime, double> uncategorizedByDay,
  required final Map<DateTime, double> totalByDay,
}) {
  static CategorySpendDailyMaps fromTransactions({
    required List<BankTransaction> transactions,
    required Set<String> flowCategoryIds,
  }) {
    final byCategoryId = <String, Map<DateTime, double>>{};
    final uncategorizedByDay = <DateTime, double>{};
    final totalByDay = <DateTime, double>{};

    for (final transaction in transactions) {
      // Outflows add spend; inflows in a spend category subtract (refunds).
      if (transaction.excluded || transaction.isZeroAmount) continue;
      final categoryId = transaction.categoryId;
      if (categoryId != null && flowCategoryIds.contains(categoryId)) {
        continue;
      }

      final day = transaction.postedAt.startOfDay;
      final spendCents = -transaction.amountCents.toDouble();
      totalByDay.update(
        day,
        (priorSpendCents) => priorSpendCents + spendCents,
        ifAbsent: () => spendCents,
      );

      if (categoryId == null) {
        uncategorizedByDay.update(
          day,
          (priorSpendCents) => priorSpendCents + spendCents,
          ifAbsent: () => spendCents,
        );
        continue;
      }

      byCategoryId
          .putIfAbsent(categoryId, () => {})
          .update(
            day,
            (priorSpendCents) => priorSpendCents + spendCents,
            ifAbsent: () => spendCents,
          );
    }

    return CategorySpendDailyMaps(
      byCategoryId: byCategoryId,
      uncategorizedByDay: uncategorizedByDay,
      totalByDay: totalByDay,
    );
  }
}

/// Builds category / group / all-spend / affordability guide series.
class const CategorySpendTrendBuilder({
  required final CategorySpendDailyMaps spendMaps,
  required final Map<DateTime, double> incomeByDay,
  required final List<SpendCategory> categories,
  required final List<CategoryGroup> groups,
  required final Set<String> flowCategoryIds,
  required final List<DateTime> chartDates,
  required final DateTime historyFloor,
}) {
  /// Ten high-chroma hues for dark backgrounds (not All / Uncategorized).
  static const _palette = <Color>[
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

  List<CategoryTrendSeries> build() {
    if (spendMaps.totalByDay.isEmpty) return const [];

    final allSpendSeries = _paceSeries(
      id: TrendChartCatalog.allSpendSeriesId,
      name: 'All spending',
      lineColor: TrendChartCatalog.allSpendLineColor,
      dotted: true,
      dailyCents: spendMaps.totalByDay,
    );

    final housingAffordabilitySeries = _housingAffordabilitySeries();
    final partitioned = _partitionCategories();
    final rankedSeries = _rankedGroupAndCategorySeries(partitioned);
    final uncategorizedSeries = _uncategorizedSeries();

    return [
      allSpendSeries,
      ?housingAffordabilitySeries,
      ...rankedSeries,
      ?uncategorizedSeries,
    ];
  }

  CategoryTrendSeries? _housingAffordabilitySeries() {
    if (incomeByDay.isEmpty) return null;
    final affordabilityDaily = {
      for (final entry in incomeByDay.entries)
        entry.key: entry.value * TrendChartCatalog.housingIncomeShareCap,
    };
    final built = _paceSeries(
      id: TrendChartCatalog.housingAffordabilitySeriesId,
      name: '30% of income',
      lineColor: TrendChartCatalog.housingAffordabilityLineColor,
      guide: true,
      dailyCents: affordabilityDaily,
    );
    return built.hasMeaningfulTrend ? built : null;
  }

  _CategoryPartition _partitionCategories() {
    final groupsById = {for (final group in groups) group.id: group};
    final membersByGroupId = <String, List<SpendCategory>>{};
    final ungroupedCategories = <SpendCategory>[];

    for (final category in categories) {
      if (flowCategoryIds.contains(category.id)) continue;
      final groupId = category.groupId;
      if (groupId != null && groupsById.containsKey(groupId)) {
        membersByGroupId.putIfAbsent(groupId, () => []).add(category);
      } else {
        ungroupedCategories.add(category);
      }
    }
    return _CategoryPartition(
      membersByGroupId: membersByGroupId,
      ungroupedCategories: ungroupedCategories,
    );
  }

  List<CategoryTrendSeries> _rankedGroupAndCategorySeries(
    _CategoryPartition partitioned,
  ) {
    final seriesBlocks = <List<CategoryTrendSeries>>[];
    var paletteIndex = 0;

    for (final group in groups) {
      final members = partitioned.membersByGroupId[group.id];
      if (members == null || members.isEmpty) continue;

      final groupDaily = <DateTime, double>{};
      final memberSeries = <CategoryTrendSeries>[];
      for (final member in members) {
        final memberDaily = spendMaps.byCategoryId[member.id];
        if (memberDaily == null || memberDaily.isEmpty) continue;
        _mergeDailyMaps(groupDaily, memberDaily);

        final memberIsHousing = member.isHousing;
        final builtMember = _paceSeries(
          id: member.id,
          name: member.name,
          lineColor: memberIsHousing
              ? CategoryColor.housing
              : CategoryColor.forCategory(member),
          dailyCents: memberDaily,
          memberOfGroupSeriesId: TrendChartCatalog.groupSeriesId(group.id),
        );
        if (!builtMember.hasMeaningfulTrend) {
          continue;
        }
        memberSeries.add(builtMember);
      }
      if (groupDaily.isEmpty) continue;

      final groupIsHousing = members.any((member) => member.isHousing);
      final groupSeries = _paceSeries(
        id: TrendChartCatalog.groupSeriesId(group.id),
        name: group.name,
        lineColor: groupIsHousing
            ? CategoryColor.housing
            : CategoryColor.forGroupId(group.id),
        dailyCents: groupDaily,
      );
      if (!groupSeries.hasMeaningfulTrend) continue;

      memberSeries.sort(
        (left, right) =>
            right.latestSmoothedCents.compareTo(left.latestSmoothedCents),
      );
      seriesBlocks.add([groupSeries, ...memberSeries]);
    }

    for (final category in partitioned.ungroupedCategories) {
      final dailySpendCents = spendMaps.byCategoryId[category.id];
      if (dailySpendCents == null || dailySpendCents.isEmpty) continue;

      final pinnedColor = category.isHousing ? CategoryColor.housing : null;
      final categorySeries = _paceSeries(
        id: category.id,
        name: category.name,
        lineColor: pinnedColor ?? _palette[paletteIndex % _palette.length],
        dailyCents: dailySpendCents,
      );
      if (!categorySeries.hasMeaningfulTrend) {
        continue;
      }
      if (pinnedColor == null) paletteIndex++;
      seriesBlocks.add([categorySeries]);
    }

    seriesBlocks.sort(
      (left, right) => right.first.latestSmoothedCents.compareTo(
        left.first.latestSmoothedCents,
      ),
    );

    return [for (final block in seriesBlocks) ...block];
  }

  CategoryTrendSeries? _uncategorizedSeries() {
    if (spendMaps.uncategorizedByDay.isEmpty) return null;

    final built = _paceSeries(
      id: TrendChartCatalog.uncategorizedSeriesId,
      name: 'Uncategorized',
      lineColor: TrendChartCatalog.uncategorizedLineColor,
      dailyCents: spendMaps.uncategorizedByDay,
    );
    return built.hasMeaningfulTrend ? built : null;
  }

  CategoryTrendSeries _paceSeries({
    required String id,
    required String name,
    required Color lineColor,
    required Map<DateTime, double> dailyCents,
    bool dotted = false,
    bool guide = false,
    String? memberOfGroupSeriesId,
  }) {
    return AnnualPaceSmoother.standard.seriesFromDailyMap(
      id: id,
      name: name,
      lineColor: lineColor,
      dotted: dotted,
      guide: guide,
      dailyCents: dailyCents,
      chartDates: chartDates,
      historyFloor: historyFloor,
      memberOfGroupSeriesId: memberOfGroupSeriesId,
    );
  }

  static void _mergeDailyMaps(
    Map<DateTime, double> into,
    Map<DateTime, double> from,
  ) {
    for (final entry in from.entries) {
      into.update(
        entry.key,
        (priorCents) => priorCents + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }
}

class const _CategoryPartition({
  required final Map<String, List<SpendCategory>> membersByGroupId,
  required final List<SpendCategory> ungroupedCategories,
});
