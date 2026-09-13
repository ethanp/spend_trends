import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/trends/category_trend_distribution_legend.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/trend_legend_swatch.dart';
import 'package:spend_trends/theme/finance_colors.dart';

/// Legend under a trends chart: meta chips, plus ranked chips or distribution.
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
        ? _NetWorthLegendTable(
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
        fillAvailableWidth: true,
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
      fillAvailableWidth: stackVertically,
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

class const TrendLegendChip({
  required final CategoryTrendSeries series,
  required final bool isHidden,
  required final TrendSpendRate spendRate,
  required final VoidCallback onActivated,
  required final VoidCallback onSoloActivated,
  final TrendValueKind valueKind = TrendValueKind.pace,
  final DateTime? inspectDate,
  final bool expandLabel = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Level charts (net worth): show current rolling balance, not CMA tip —
    // the tip window averages prior days and drifts from today's Banks total.
    final cents = CategoryTrendLegendAmount(
      series: series,
      valueKind: valueKind,
      inspectDate: inspectDate,
    ).cents;
    final amountLabel = formatCentsWholeDollars(
      valueKind == TrendValueKind.level ? cents : spendRate.displayCents(cents),
    );
    final rateSuffix = valueKind == TrendValueKind.level
        ? ''
        : ' ${spendRate.shortLabel}';
    final nameStyle = isHidden
        ? EText.caption.copyWith(color: EColors.textMuted)
        : EText.caption;
    final amountStyle = valueKind == TrendValueKind.level
        ? _signedAmountStyle(cents, isHidden: isHidden)
        : nameStyle;
    final label = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: series.name, style: nameStyle),
          TextSpan(text: ' · ', style: nameStyle),
          TextSpan(text: '$amountLabel$rateSuffix', style: amountStyle),
          if (series.legendCaption != null) ...[
            TextSpan(text: ' · ', style: nameStyle),
            TextSpan(text: series.legendCaption, style: nameStyle),
          ],
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: expandLabel ? TextOverflow.ellipsis : TextOverflow.visible,
    );
    return GestureDetector(
      onTap: onActivated,
      onDoubleTap: onSoloActivated,
      child: Row(
        mainAxisSize: expandLabel ? MainAxisSize.max : MainAxisSize.min,
        children: [
          TrendLegendSwatch(series: series, isHidden: isHidden),
          const SizedBox(width: ELayout.spaceXs),
          if (expandLabel) Expanded(child: label) else label,
        ],
      ),
    );
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
  final bool fillAvailableWidth = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final chips = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < metaSeries.length; index++) ...[
          if (index > 0) const SizedBox(height: ELayout.spaceSm),
          TrendLegendChip(
            series: metaSeries[index],
            isHidden: hiddenSeriesIds.contains(metaSeries[index].id),
            spendRate: spendRate,
            valueKind: valueKind,
            inspectDate: inspectDate,
            expandLabel: fillAvailableWidth,
            onActivated: () => onSeriesToggled(metaSeries[index].id),
            onSoloActivated: () => onSeriesSoloed(metaSeries[index].id),
          ),
        ],
      ],
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
      child: fillAvailableWidth ? chips : IntrinsicWidth(child: chips),
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
    return Wrap(
      spacing: ELayout.spaceMd,
      runSpacing: ELayout.spaceSm,
      children: [
        for (final series in seriesList)
          TrendLegendChip(
            series: series,
            isHidden: hiddenSeriesIds.contains(series.id),
            spendRate: spendRate,
            valueKind: valueKind,
            inspectDate: inspectDate,
            expandLabel: false,
            onActivated: () => onSeriesToggled(series.id),
            onSoloActivated: () => onSeriesSoloed(series.id),
          ),
      ],
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

/// Net worth account rows as a signed-amount table, grouped by account kind.
class const _NetWorthLegendTable({
  required final List<CategoryTrendSeries> seriesList,
  required final Set<String> hiddenSeriesIds,
  required final TrendValueKind valueKind,
  required final DateTime? inspectDate,
  required final ValueChanged<String> onSeriesToggled,
  required final ValueChanged<String> onSeriesSoloed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final groups = _groupsFromSeries(seriesList);
    final showSectionLabels =
        groups.length > 1 ||
        (groups.length == 1 && groups.first.sectionName != 'Other');

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
      child: Table(
        columnWidths: const {0: FlexColumnWidth(), 1: IntrinsicColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (
            var groupIndex = 0;
            groupIndex < groups.length;
            groupIndex++
          ) ...[
            if (showSectionLabels)
              _sectionHeaderRow(
                groups[groupIndex].sectionName,
                padTop: groupIndex > 0,
              ),
            for (final series in groups[groupIndex].seriesList)
              _accountRow(series),
          ],
        ],
      ),
    );
  }

  TableRow _sectionHeaderRow(String sectionName, {required bool padTop}) {
    return TableRow(
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: padTop ? ELayout.spaceSm : 0,
            bottom: ELayout.spaceXs,
          ),
          child: Text(
            sectionName,
            style: EText.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: FinanceColors.accentPrimary,
            ),
          ),
        ),
        const SizedBox.shrink(),
      ],
    );
  }

  TableRow _accountRow(CategoryTrendSeries series) {
    final isHidden = hiddenSeriesIds.contains(series.id);
    final cents = CategoryTrendLegendAmount(
      series: series,
      valueKind: valueKind,
      inspectDate: inspectDate,
    ).cents;
    return TableRow(
      children: [
        GestureDetector(
          onTap: () => onSeriesToggled(series.id),
          onDoubleTap: () => onSeriesSoloed(series.id),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ELayout.spaceXs),
            child: Row(
              children: [
                TrendLegendSwatch(series: series, isHidden: isHidden),
                const SizedBox(width: ELayout.spaceSm),
                Expanded(
                  child: Text(
                    series.name,
                    style: isHidden
                        ? EText.caption.copyWith(color: EColors.textMuted)
                        : EText.caption.copyWith(color: EColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: () => onSeriesToggled(series.id),
          onDoubleTap: () => onSeriesSoloed(series.id),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(
              left: ELayout.spaceMd,
              top: ELayout.spaceXs,
              bottom: ELayout.spaceXs,
            ),
            child: Text(
              formatCentsWholeDollars(cents),
              style: _signedAmountStyle(
                cents,
                isHidden: isHidden,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ],
    );
  }

  static List<_LegendSectionGroup> _groupsFromSeries(
    List<CategoryTrendSeries> seriesList,
  ) {
    final byName = <String, List<CategoryTrendSeries>>{};
    final sectionOrder = <String>[];
    for (final series in seriesList) {
      final key = series.legendGroup?.trim();
      final sectionName = key == null || key.isEmpty ? 'Other' : key;
      if (!byName.containsKey(sectionName)) {
        sectionOrder.add(sectionName);
        byName[sectionName] = [];
      }
      byName[sectionName]!.add(series);
    }
    return [
      for (final name in sectionOrder)
        _LegendSectionGroup(
          sectionName: name,
          seriesList: _sortedByMagnitudeDesc(byName[name]!),
        ),
    ];
  }

  static List<CategoryTrendSeries> _sortedByMagnitudeDesc(
    List<CategoryTrendSeries> seriesList,
  ) {
    final sorted = [...seriesList];
    sorted.sort((left, right) {
      final leftCents = CategoryTrendLegendAmount(
        series: left,
        valueKind: TrendValueKind.level,
      ).cents.abs();
      final rightCents = CategoryTrendLegendAmount(
        series: right,
        valueKind: TrendValueKind.level,
      ).cents.abs();
      return rightCents.compareTo(leftCents);
    });
    return sorted;
  }
}

class const _LegendSectionGroup({
  required final String sectionName,
  required final List<CategoryTrendSeries> seriesList,
});

/// Signed legend amount: latest when idle, nearest point when inspecting.
class const CategoryTrendLegendAmount({
  required final CategoryTrendSeries series,
  required final TrendValueKind valueKind,
  final DateTime? inspectDate,
}) {
  int get cents {
    final inspectDay = inspectDate;
    final point = inspectDay == null ? null : series.nearestPoint(inspectDay);
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

  bool get _isLiability {
    if (series.dotted) return true;
    final group = series.legendGroup;
    return group == AccountKind.creditCard.legendLabel ||
        group == AccountKind.loans.legendLabel;
  }
}

TextStyle _signedAmountStyle(int cents, {required bool isHidden}) {
  final base = EText.caption.copyWith(fontWeight: FontWeight.w600);
  if (isHidden) {
    return base.copyWith(color: EColors.textMuted);
  }
  if (cents > 0) return base.copyWith(color: EColors.success);
  if (cents < 0) return base.copyWith(color: EColors.danger);
  return base;
}
