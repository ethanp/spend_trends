import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/category_trend_series_legend.dart';
import 'package:spend_trends/features/trends/trend_legend_swatch.dart';
import 'package:spend_trends/theme/finance_colors.dart';

/// Net worth account rows as a signed-amount table, grouped by account kind.
/// Sections start folded to their header and total; tap a header to unfold.
class const NetWorthLegendTable({
  required final List<CategoryTrendSeries> seriesList,
  required final Set<String> hiddenSeriesIds,
  required final TrendValueKind valueKind,
  required final DateTime? inspectDate,
  required final ValueChanged<String> onSeriesToggled,
  required final ValueChanged<String> onSeriesSoloed,
}) extends StatefulWidget {
  @override
  State<NetWorthLegendTable> createState() => _NetWorthLegendTableState();
}

class _NetWorthLegendTableState() extends State<NetWorthLegendTable> {
  final Set<String> _unfoldedSectionNames = {};

  @override
  Widget build(BuildContext context) {
    final List<_LegendSection> sections = _sectionsFromSeries();
    final bool showSectionHeaders =
        sections.length > 1 ||
        (sections.length == 1 && sections.first.sectionName != 'Other');

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
          for (final section in sections)
            if (showSectionHeaders) ...[
              _sectionHeaderRow(section, padTop: section != sections.first),
              if (_unfoldedSectionNames.contains(section.sectionName))
                for (final series in section.seriesList) _accountRow(series),
            ] else
              for (final series in section.seriesList) _accountRow(series),
        ],
      ),
    );
  }

  void _toggleSectionFold(String sectionName) {
    setState(() {
      if (!_unfoldedSectionNames.remove(sectionName)) {
        _unfoldedSectionNames.add(sectionName);
      }
    });
  }

  TableRow _sectionHeaderRow(_LegendSection section, {required bool padTop}) {
    final bool isUnfolded = _unfoldedSectionNames.contains(section.sectionName);
    final rowPadding = EdgeInsets.only(
      top: padTop ? ELayout.spaceSm : 0,
      bottom: ELayout.spaceXs,
    );
    return TableRow(
      children: [
        _foldToggle(
          section.sectionName,
          child: Padding(
            padding: rowPadding,
            child: Row(
              children: [
                Icon(
                  isUnfolded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: FinanceColors.accentPrimary,
                ),
                const SizedBox(width: ELayout.spaceXs),
                Text(
                  '${section.sectionName} · ${section.seriesList.length}',
                  style: EText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: FinanceColors.accentPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        _foldToggle(
          section.sectionName,
          child: Padding(
            padding: rowPadding.copyWith(left: ELayout.spaceMd),
            child: _amountText(_sectionTotalCents(section), isHidden: false),
          ),
        ),
      ],
    );
  }

  Widget _foldToggle(String sectionName, {required Widget child}) {
    return GestureDetector(
      onTap: () => _toggleSectionFold(sectionName),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }

  TableRow _accountRow(CategoryTrendSeries series) {
    final bool isHidden = widget.hiddenSeriesIds.contains(series.id);
    return TableRow(
      children: [
        _seriesToggle(
          series,
          child: Padding(
            padding: const EdgeInsets.only(
              left: ELayout.spaceMd,
              top: ELayout.spaceXs,
              bottom: ELayout.spaceXs,
            ),
            child: Row(
              children: [
                TrendLegendSwatch(series: series, isHidden: isHidden),
                const SizedBox(width: ELayout.spaceSm),
                Expanded(
                  child: Text(
                    series.name,
                    style: EText.caption.copyWith(
                      color: isHidden ? EColors.textMuted : EColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        _seriesToggle(
          series,
          child: Padding(
            padding: const EdgeInsets.only(
              left: ELayout.spaceMd,
              top: ELayout.spaceXs,
              bottom: ELayout.spaceXs,
            ),
            child: _amountText(_legendAmount(series).cents, isHidden: isHidden),
          ),
        ),
      ],
    );
  }

  Widget _seriesToggle(CategoryTrendSeries series, {required Widget child}) {
    return GestureDetector(
      onTap: () => widget.onSeriesToggled(series.id),
      onDoubleTap: () => widget.onSeriesSoloed(series.id),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }

  Widget _amountText(int cents, {required bool isHidden}) {
    return Text(
      formatCentsWholeDollars(cents),
      style: CategoryTrendLegendAmount.signedAmountStyle(
        cents,
        isHidden: isHidden,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      textAlign: TextAlign.right,
    );
  }

  /// Signed sum, so liabilities net against assets in mixed sections.
  int _sectionTotalCents(_LegendSection section) {
    var totalCents = 0;
    for (final series in section.seriesList) {
      totalCents += _legendAmount(series).cents;
    }
    return totalCents;
  }

  CategoryTrendLegendAmount _legendAmount(CategoryTrendSeries series) =>
      CategoryTrendLegendAmount(
        series: series,
        valueKind: widget.valueKind,
        inspectDate: widget.inspectDate,
      );

  List<_LegendSection> _sectionsFromSeries() {
    final seriesBySectionName = <String, List<CategoryTrendSeries>>{};
    for (final series in widget.seriesList) {
      final String? legendGroup = series.legendGroup?.trim();
      final sectionName = legendGroup == null || legendGroup.isEmpty
          ? 'Other'
          : legendGroup;
      seriesBySectionName.putIfAbsent(sectionName, () => []).add(series);
    }
    return [
      for (final MapEntry(key: sectionName, value: sectionSeries)
          in seriesBySectionName.entries)
        _LegendSection(
          sectionName: sectionName,
          seriesList: _sortedByMagnitudeDesc(sectionSeries),
        ),
    ];
  }

  List<CategoryTrendSeries> _sortedByMagnitudeDesc(
    List<CategoryTrendSeries> seriesList,
  ) {
    int latestMagnitude(CategoryTrendSeries series) =>
        CategoryTrendLegendAmount(
          series: series,
          valueKind: TrendValueKind.level,
        ).cents.abs();
    return [...seriesList]..sort(
      (left, right) => latestMagnitude(right).compareTo(latestMagnitude(left)),
    );
  }
}

class const _LegendSection({
  required final String sectionName,
  required final List<CategoryTrendSeries> seriesList,
});
