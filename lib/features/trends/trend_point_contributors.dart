import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/cash_flow_breakdown.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/annual_pace_smoother.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:ethan_utils/ethan_utils.dart';

/// One transaction's contribution to a trendline at a tap date.
class const TrendPointContributor({
  required final BankTransaction transaction,
  required final double smoothedContributionCents,
  required final int rawAmountCents,
});

/// Resolves top transactions feeding a series' smoothed pace at [tapDate].
class TrendPointContributors._() {
  static const topCount = 5;

  static List<TrendPointContributor> topForSeries({
    required CategoryTrendSeries series,
    required DateTime tapDate,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
    required List<CategoryGroup> groups,
    List<Account> accounts = const [],
    int limit = topCount,
  }) {
    if (series.guide || _isGuideSeriesId(series.id)) return const [];
    if (series.points.length < 2) return const [];

    final tapDay = tapDate.startOfDay;
    var tapIndex = 0;
    var bestDelta = 1 << 30;
    for (var pointIndex = 0; pointIndex < series.points.length; pointIndex++) {
      final delta = series.points[pointIndex].date
          .difference(tapDay)
          .inDays
          .abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        tapIndex = pointIndex;
      }
    }

    final historyFloor = TrendChartCatalog.chartHistoryStart.startOfDay;

    final chartDates = [
      for (final point in series.points) point.date.startOfDay,
    ];
    final dayIndexByDate = <DateTime, int>{
      for (var dayIndex = 0; dayIndex < chartDates.length; dayIndex++)
        chartDates[dayIndex]: dayIndex,
    };

    var historyStartIndex = 0;
    while (historyStartIndex < chartDates.length &&
        chartDates[historyStartIndex].isBefore(historyFloor)) {
      historyStartIndex++;
    }
    const smoother = AnnualPaceSmoother.standard;
    final support = smoother.supportSpan(
      centerIndex: tapIndex,
      historyStartIndex: historyStartIndex,
      lastDayIndex: chartDates.length - 1,
    );
    final windowStartDay = chartDates[support.startIndex];
    final windowEndDay = chartDates[support.endIndex];

    final membership = _membershipForSeries(
      seriesId: series.id,
      categories: categories,
      groups: groups,
    );
    if (membership == null) return const [];
    final cashFlowBreakdown = CashFlowBreakdown(
      categories: categories,
      accounts: accounts,
    );

    final candidates = <BankTransaction>[];
    for (final transaction in transactions) {
      final day = transaction.postedAt.startOfDay;
      if (day.isBefore(windowStartDay) || day.isAfter(windowEndDay)) continue;
      if (membership.signedAmountCents(transaction, cashFlowBreakdown) == 0) {
        continue;
      }
      candidates.add(transaction);
    }
    if (candidates.isEmpty) return const [];

    final contributors = <TrendPointContributor>[];
    for (final transaction in candidates) {
      final signedAmount = membership.signedAmountCents(
        transaction,
        cashFlowBreakdown,
      );
      final txnIndex = dayIndexByDate[transaction.postedAt.startOfDay];
      if (txnIndex == null) continue;
      final smoothedContribution = smoother.impulseContributionCents(
        amountCents: signedAmount.toDouble(),
        impulseIndex: txnIndex,
        tapIndex: tapIndex,
        historyStartIndex: historyStartIndex,
        lastDayIndex: chartDates.length - 1,
      );
      if (smoothedContribution.abs() < 0.5) continue;
      contributors.add(
        TrendPointContributor(
          transaction: transaction,
          smoothedContributionCents: smoothedContribution,
          rawAmountCents: transaction.amountCents,
        ),
      );
    }

    contributors.sort((left, right) {
      final byContribution = right.smoothedContributionCents.abs().compareTo(
        left.smoothedContributionCents.abs(),
      );
      if (byContribution != 0) return byContribution;
      return right.transaction.postedAt.compareTo(left.transaction.postedAt);
    });
    if (contributors.length <= limit) return contributors;
    return contributors.sublist(0, limit);
  }

  static bool _isGuideSeriesId(String seriesId) =>
      seriesId == TrendChartCatalog.housingAffordabilitySeriesId ||
      seriesId == TrendChartCatalog.fireSavingsGuideSeriesId;

  static _SeriesMembership? _membershipForSeries({
    required String seriesId,
    required List<SpendCategory> categories,
    required List<CategoryGroup> groups,
  }) {
    if (seriesId == TrendChartCatalog.allSpendSeriesId) {
      return const _SeriesMembership.categorySpend(categoryIds: null);
    }
    if (seriesId == TrendChartCatalog.uncategorizedSeriesId) {
      return const _SeriesMembership.uncategorized();
    }
    if (seriesId == TrendChartCatalog.incomeSeriesId) {
      return const _SeriesMembership.cashFlow(_CashFlowLine.takeHome);
    }
    if (seriesId == TrendChartCatalog.spendingSeriesId) {
      return const _SeriesMembership.cashFlow(_CashFlowLine.spending);
    }
    if (seriesId == TrendChartCatalog.transferSeriesId) {
      return const _SeriesMembership.cashFlow(_CashFlowLine.transfer);
    }
    if (seriesId == TrendChartCatalog.savingsSeriesId) {
      return const _SeriesMembership.cashFlow(_CashFlowLine.savings);
    }
    if (seriesId.startsWith(TrendChartCatalog.groupSeriesIdPrefix)) {
      final groupId = seriesId.substring(
        TrendChartCatalog.groupSeriesIdPrefix.length,
      );
      final memberIds = {
        for (final category in categories)
          if (category.groupId == groupId) category.id,
      };
      if (memberIds.isEmpty) return null;
      return _SeriesMembership.categorySpend(categoryIds: memberIds);
    }
    if (seriesId.startsWith(
      TrendChartCatalog.consciousSpendingAreaSeriesIdPrefix,
    )) {
      final areaName = seriesId.substring(
        TrendChartCatalog.consciousSpendingAreaSeriesIdPrefix.length,
      );
      final area = ConsciousSpendingArea.fromStorage(areaName);
      if (area == null) return null;
      return _SeriesMembership.consciousSpendingArea(area);
    }
    if (seriesId.startsWith('__')) return null;
    return _SeriesMembership.categorySpend(categoryIds: {seriesId});
  }
}

enum _MembershipKind() {
  categorySpend,
  uncategorized,
  cashFlow,
  consciousSpendingArea,
}

/// Cash-flow chart lines, each read off a [CashFlowContribution].
enum _CashFlowLine() {
  takeHome,
  spending,
  transfer,
  savings;

  int centsOf(CashFlowContribution contribution) => switch (this) {
    _CashFlowLine.takeHome => contribution.takeHomeCents,
    _CashFlowLine.spending => contribution.spendingCents,
    _CashFlowLine.transfer => contribution.transferCents,
    _CashFlowLine.savings => contribution.savingsCents,
  };
}

class const _SeriesMembership._({
  required final _MembershipKind kind,
  final Set<String>? categoryIds,
  final _CashFlowLine? cashFlowLine,
  final ConsciousSpendingArea? area,
}) {
  const new categorySpend({required Set<String>? categoryIds})
    : this._(kind: _MembershipKind.categorySpend, categoryIds: categoryIds);

  const new uncategorized() : this._(kind: _MembershipKind.uncategorized);

  const new cashFlow(_CashFlowLine cashFlowLine)
    : this._(kind: _MembershipKind.cashFlow, cashFlowLine: cashFlowLine);

  const new consciousSpendingArea(ConsciousSpendingArea area)
    : this._(kind: _MembershipKind.consciousSpendingArea, area: area);

  /// This transaction's signed share of the line; 0 means not a member.
  int signedAmountCents(
    BankTransaction transaction,
    CashFlowBreakdown cashFlowBreakdown,
  ) {
    switch (kind) {
      case _MembershipKind.categorySpend:
        if (transaction.excluded || transaction.isZeroAmount) return 0;
        final categoryId = transaction.categoryId;
        if (SpecialCategory.isFlowId(categoryId)) return 0;
        if (categoryIds != null &&
            (categoryId == null || !categoryIds!.contains(categoryId))) {
          return 0;
        }
        return -transaction.amountCents;
      case _MembershipKind.uncategorized:
        if (transaction.excluded || !transaction.isUncategorized) return 0;
        return -transaction.amountCents;
      case _MembershipKind.cashFlow:
        return cashFlowLine!.centsOf(
          cashFlowBreakdown.contributionOf(transaction),
        );
      case _MembershipKind.consciousSpendingArea:
        final contribution = cashFlowBreakdown.contributionOf(transaction);
        return contribution.area == area ? contribution.areaCents : 0;
    }
  }
}
