import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:spend_trends/domain/trends/trend_spend_rate.dart';
import 'package:spend_trends/ui/trends/category_trend_distribution_legend.dart';
import 'package:spend_trends/ui/trends/category_trend_series.dart';
import 'package:spend_trends/ui/trends/net_worth_legend_table.dart';
import 'package:spend_trends/ui/trends/trend_legend_swatch.dart';
import 'package:spend_trends/ui/trends/trend_spend_rate_toggle.dart';

/// Legend under a trends chart: meta chips, plus ranked chips or distribution.
/// Pace legends lead with the yr/mo/day toggle their amounts are shown in.
class const CategoryTrendSeriesLegend({
  required final List<CategoryTrendSeries> seriesList,
  required final Set<String> hiddenSeriesIds,
  required final TrendSpendRate spendRate,
  required final bool useDistributionLegend,
  required final ValueChanged<String> onSeriesToggled,
  required final ValueChanged<String> onSeriesSoloed,
  final TrendValueKind valueKind = TrendValueKind.pace,
  final DateTime? inspectDate,
}) extends StatelessWidget {
  static const _sideBySideMinWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    if (seriesList.isEmpty) return const SizedBox.shrink();
    if (valueKind != TrendValueKind.pace) return _seriesEntries();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerRight,
          child: TrendSpendRateToggle(),
        ),
        const SizedBox(height: ELayout.spaceSm),
        _seriesEntries(),
      ],
    );
  }

  Widget _seriesEntries() {
    final metaSeries = [
      for (final series in seriesList)
        if (series.isMetaLegend) series,
    ];
    final rankedSeries = [
      for (final series in seriesList)
        if (!series.isMetaLegend) series,
    ];

    final useNetWorthTable =
        !useDistributionLegend && _rankedSeriesHasLegendGroups(rankedSeries);

    final rankedChild = rankedSeries.isEmpty
        ? null
        : useDistributionLegend
        ? CategoryTrendDistributionLegend(
            seriesList: rankedSeries,
            hiddenSeriesIds: hiddenSeriesIds,
            spendRate: spendRate,
            onSeriesToggled: onSeriesToggled,
            onSeriesSoloed: onSeriesSoloed,
          )
        : useNetWorthTable
        ? NetWorthLegendTable(
            seriesList: rankedSeries,
            hiddenSeriesIds: hiddenSeriesIds,
            valueKind: valueKind,
            inspectDate: inspectDate,
            onSeriesToggled: onSeriesToggled,
            onSeriesSoloed: onSeriesSoloed,
          )
        : _WrappingLegend(
            seriesList: rankedSeries,
            hiddenSeriesIds: hiddenSeriesIds,
            spendRate: spendRate,
            valueKind: valueKind,
            inspectDate: inspectDate,
            onSeriesToggled: onSeriesToggled,
            onSeriesSoloed: onSeriesSoloed,
          );

    if (metaSeries.isEmpty) return rankedChild!;
    if (rankedChild == null) {
      return _MetaLegendColumn(
        metaSeries: metaSeries,
        hiddenSeriesIds: hiddenSeriesIds,
        spendRate: spendRate,
        valueKind: valueKind,
        inspectDate: inspectDate,
        onSeriesToggled: onSeriesToggled,
        onSeriesSoloed: onSeriesSoloed,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => _metaAndRanked(
        stackVertically: constraints.maxWidth < _sideBySideMinWidth,
        metaSeries: metaSeries,
        rankedChild: rankedChild,
      ),
    );
  }

  Widget _metaAndRanked({
    required bool stackVertically,
    required List<CategoryTrendSeries> metaSeries,
    required Widget rankedChild,
  }) {
    final metaColumn = _MetaLegendColumn(
      metaSeries: metaSeries,
      hiddenSeriesIds: hiddenSeriesIds,
      spendRate: spendRate,
      valueKind: valueKind,
      inspectDate: inspectDate,
      onSeriesToggled: onSeriesToggled,
      onSeriesSoloed: onSeriesSoloed,
    );

    if (stackVertically) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          metaColumn,
          const SizedBox(height: ELayout.spaceMd),
          rankedChild,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        metaColumn,
        const SizedBox(width: ELayout.spaceMd),
        const _LegendColumnDivider(height: 72),
        const SizedBox(width: ELayout.spaceMd),
        Expanded(child: rankedChild),
      ],
    );
  }

  static bool _rankedSeriesHasLegendGroups(
    List<CategoryTrendSeries> seriesList,
  ) {
    for (final series in seriesList) {
      if (series.legendGroup != null) return true;
    }
    return false;
  }
}

class const _MetaLegendColumn({
  required final List<CategoryTrendSeries> metaSeries,
  required final Set<String> hiddenSeriesIds,
  required final TrendSpendRate spendRate,
  required final TrendValueKind valueKind,
  required final DateTime? inspectDate,
  required final ValueChanged<String> onSeriesToggled,
  required final ValueChanged<String> onSeriesSoloed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final legend = EChartLegend(
      entries: _SeriesLegendEntries(
        seriesList: metaSeries,
        hiddenSeriesIds: hiddenSeriesIds,
        spendRate: spendRate,
        valueKind: valueKind,
        inspectDate: inspectDate,
        onSeriesToggled: onSeriesToggled,
        onSeriesSoloed: onSeriesSoloed,
      ).entries,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ELayout.spaceSm,
        vertical: ELayout.spaceXs,
      ),
      decoration: BoxDecoration(
        color: EColors.surface.withValues(alpha: 0.55),
        borderRadius: ELayout.borderRadiusSm,
        border: Border.all(color: EColors.border.withValues(alpha: 0.7)),
      ),
      child: legend,
    );
  }
}

class const _WrappingLegend({
  required final List<CategoryTrendSeries> seriesList,
  required final Set<String> hiddenSeriesIds,
  required final TrendSpendRate spendRate,
  required final TrendValueKind valueKind,
  required final DateTime? inspectDate,
  required final ValueChanged<String> onSeriesToggled,
  required final ValueChanged<String> onSeriesSoloed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return EChartLegend(
      entries: _SeriesLegendEntries(
        seriesList: seriesList,
        hiddenSeriesIds: hiddenSeriesIds,
        spendRate: spendRate,
        valueKind: valueKind,
        inspectDate: inspectDate,
        onSeriesToggled: onSeriesToggled,
        onSeriesSoloed: onSeriesSoloed,
      ).entries,
    );
  }
}

class const _SeriesLegendEntries({
  required final List<CategoryTrendSeries> seriesList,
  required final Set<String> hiddenSeriesIds,
  required final TrendSpendRate spendRate,
  required final TrendValueKind valueKind,
  required final DateTime? inspectDate,
  required final ValueChanged<String> onSeriesToggled,
  required final ValueChanged<String> onSeriesSoloed,
}) {
  List<EChartLegendEntry> get entries => seriesList.mapL(_entry);

  EChartLegendEntry _entry(CategoryTrendSeries series) {
    final isHidden = hiddenSeriesIds.contains(series.id);
    final amount = CategoryTrendLegendAmount(
      series: series,
      valueKind: valueKind,
      inspectDate: inspectDate,
    );
    return EChartLegendEntry(
      swatch: TrendLegendSwatch(series: series, isHidden: isHidden),
      label: series.name,
      labelStyle: isHidden ? _hiddenLegendText : null,
      value: amount.formatted(spendRate),
      valueStyle: _legendValueStyle(
        cents: amount.cents,
        isHidden: isHidden,
        valueKind: valueKind,
      ),
      caption: series.legendCaption,
      dimmed: isHidden,
      onActivated: () => onSeriesToggled(series.id),
      onDoubleActivated: () => onSeriesSoloed(series.id),
    );
  }
}

class const _LegendColumnDivider({final double? height})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      color: EColors.border.withValues(alpha: 0.8),
    );
  }
}

/// Signed legend amount: latest when idle, nearest point when inspecting.
class const CategoryTrendLegendAmount({
  required final CategoryTrendSeries series,
  required final TrendValueKind valueKind,
  final DateTime? inspectDate,
}) {
  int get cents {
    final inspectDay = inspectDate;
    final point = inspectDay == null ? null : series.nearestPoint(inspectDay);
    // Level charts show the rolling balance. The smoothed tip averages prior
    // days and drifts from today's total.
    final raw = valueKind == TrendValueKind.level
        ? (point?.rollingCents ?? series.latestRollingCents)
        : (point?.smoothedCents ?? series.latestSmoothedCents);
    final cents = raw.round();
    // Net worth liabilities are plotted as abs magnitude (often with a dotted
    // stroke). Restore a signed debt for legend amounts / colors.
    if (valueKind == TrendValueKind.level && _isLiability) {
      return -cents.abs();
    }
    return cents;
  }

  String formatted(TrendSpendRate spendRate) {
    final shownCents = valueKind == TrendValueKind.level
        ? cents
        : spendRate.displayCents(cents);
    final amountLabel = formatCentsWholeDollars(shownCents);
    if (valueKind == TrendValueKind.level) return amountLabel;
    return '$amountLabel ${spendRate.shortLabel}';
  }

  /// Assets read green, debts red; hidden rows go muted.
  static TextStyle signedAmountStyle(int cents, {required bool isHidden}) {
    final base = EText.caption.copyWith(fontWeight: FontWeight.w600);
    if (isHidden) return base.copyWith(color: EColors.textMuted);
    if (cents > 0) return base.copyWith(color: EColors.success);
    if (cents < 0) return base.copyWith(color: EColors.danger);
    return base;
  }

  bool get _isLiability {
    if (series.dotted) return true;
    final group = series.legendGroup;
    return group == AccountKind.creditCard.legendLabel ||
        group == AccountKind.loans.legendLabel;
  }
}

const _hiddenLegendText = TextStyle(decoration: TextDecoration.lineThrough);

TextStyle? _legendValueStyle({
  required int cents,
  required bool isHidden,
  required TrendValueKind valueKind,
}) {
  final TextStyle? signed = valueKind == TrendValueKind.level
      ? CategoryTrendLegendAmount.signedAmountStyle(cents, isHidden: isHidden)
      : null;
  if (!isHidden) return signed;
  final shown = signed ?? EText.caption.copyWith(fontWeight: FontWeight.w600);
  return shown.merge(_hiddenLegendText);
}
