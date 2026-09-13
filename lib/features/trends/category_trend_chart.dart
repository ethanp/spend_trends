import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/trends/category_trend_inspect_overlay.dart';
import 'package:spend_trends/features/trends/category_trend_painter.dart';
import 'package:spend_trends/features/trends/category_trend_plot.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/category_trend_series_legend.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/features/trends/trend_point_contributors.dart';
import 'package:spend_trends/features/trends/trend_point_contributors_sheet.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/help_tooltip.dart';

import 'trends_providers.dart';

/// Labeled amount shown under a Trends chart title.
class const ChartHeadlineFigure({
  required final String label,
  required final int cents,
});

/// One SimCity-style multi-line chart with a color legend.
class const CategoryTrendChart({
  required final String title,
  required final List<CategoryTrendSeries> seriesList,
  required final List<BankTransaction> transactions,
  required final List<SpendCategory> categories,
  required final List<CategoryGroup> groups,
  final List<LifeEvent> lifeEvents = const [],
  final StayChain? housingChain,
  final StayChain? jobChain,
  final String? subtitle =
      'Annual pace · tap a line for top contributors · hover to inspect · '
      'tap legend to show/hide · double-tap to solo',
  final String? titleHelp,
  final Set<String> initiallyHiddenSeriesIds = const {},

  /// When true, shows the shared yr/mo/day control (only one chart should).
  final bool showSpendRateToggle = false,

  /// Shared-scale min/med/avg/max/now whiskers for ranked category/group series.
  final bool useDistributionLegend = false,
  final TrendValueKind valueKind = TrendValueKind.pace,

  /// Tap-to-open top contributors (disabled for level charts like net worth).
  final bool enableContributors = true,

  /// Optional labeled amounts under the title (e.g. current + smoothed NW).
  final List<ChartHeadlineFigure> headlineFigures = const [],
  final double chartHeight = 560,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<CategoryTrendChart> createState() => _CategoryTrendChartState();
}

class _CategoryTrendChartState() extends ConsumerState<CategoryTrendChart> {
  static final _headlineAmountStyle = EText.section.copyWith(fontSize: 22);

  late final Set<String> _hiddenSeriesIds = {
    ...widget.initiallyHiddenSeriesIds,
  };
  late List<CategoryTrendSeries> _visibleSeries = _filterVisibleSeries();
  final ValueNotifier<CategoryTrendInspect?> _inspect = ValueNotifier(null);

  @override
  void didUpdateWidget(CategoryTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seriesList != widget.seriesList) {
      _visibleSeries = _filterVisibleSeries();
    }
  }

  @override
  void dispose() {
    _inspect.dispose();
    super.dispose();
  }

  List<CategoryTrendSeries> _filterVisibleSeries() => [
    for (final series in widget.seriesList)
      if (!_hiddenSeriesIds.contains(series.id)) series,
  ];

  @override
  Widget build(BuildContext context) {
    final TrendSpendRate spendRate = ref.watch(trendSpendRateProvider);
    return Container(
      padding: const EdgeInsets.all(ELayout.spaceMd),
      decoration: BoxDecoration(
        color: EColors.backgroundLift,
        borderRadius: ELayout.borderRadiusMd,
        border: Border.all(color: EColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(widget.title, style: EText.section)),
              if (widget.titleHelp != null) ...[
                const SizedBox(width: ELayout.spaceXs),
                HelpTooltip(message: widget.titleHelp!),
              ],
              if (widget.showSpendRateToggle) ...[
                const Spacer(),
                _spendRateToggle(spendRate),
              ],
            ],
          ),
          if (widget.headlineFigures.isNotEmpty) ...[
            const SizedBox(height: ELayout.spaceSm),
            _headlineFigures(widget.headlineFigures),
          ],
          if (widget.subtitle != null) ...[
            const SizedBox(height: ELayout.spaceXs),
            Text(widget.subtitle!, style: EText.caption),
          ],
          const SizedBox(height: ELayout.spaceMd),
          _chartArea(),
          const SizedBox(height: ELayout.spaceMd),
          ValueListenableBuilder<CategoryTrendInspect?>(
            valueListenable: _inspect,
            builder: (context, inspect, _) => CategoryTrendSeriesLegend(
              seriesList: widget.seriesList,
              hiddenSeriesIds: _hiddenSeriesIds,
              spendRate: spendRate,
              valueKind: widget.valueKind,
              useDistributionLegend: widget.useDistributionLegend,
              inspectDate: inspect?.date,
              onSeriesToggled: _toggleSeries,
              onSeriesSoloed: _soloSeries,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headlineFigures(List<ChartHeadlineFigure> figures) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var figureIndex = 0;
          figureIndex < figures.length;
          figureIndex++
        ) ...[
          if (figureIndex > 0) const SizedBox(width: ELayout.spaceXl),
          Expanded(child: _headlineFigure(figures[figureIndex])),
        ],
      ],
    );
  }

  Widget _headlineFigure(ChartHeadlineFigure figure) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(figure.label, style: EText.caption),
        const SizedBox(height: ELayout.spaceXs),
        Text(
          formatCents(figure.cents),
          style: figure.cents < 0
              ? _headlineAmountStyle.copyWith(color: EColors.danger)
              : _headlineAmountStyle,
        ),
      ],
    );
  }

  Widget _spendRateToggle(TrendSpendRate spendRate) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final rate in TrendSpendRate.values) ...[
          if (rate != TrendSpendRate.values.first)
            const SizedBox(width: ELayout.spaceXs),
          _settingsChip(
            label: rate.toggleLabel,
            isSelected: spendRate == rate,
            onActivated: () =>
                ref.read(trendSpendRateProvider.notifier).setRate(rate),
          ),
        ],
      ],
    );
  }

  Widget _settingsChip({
    required String label,
    required bool isSelected,
    required VoidCallback onActivated,
  }) {
    return GestureDetector(
      onTap: onActivated,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ELayout.spaceSm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? FinanceColors.accentPrimary.withValues(alpha: 0.25)
              : EColors.surface,
          borderRadius: ELayout.borderRadiusSm,
          border: Border.all(
            color: isSelected ? FinanceColors.accentPrimary : EColors.border,
          ),
        ),
        child: Text(
          label,
          style: EText.caption.copyWith(
            color: isSelected ? FinanceColors.accentPrimary : EColors.textMuted,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _chartArea() {
    if (!_visibleSeries.any((series) => series.canPlot)) {
      return SizedBox(
        height: widget.chartHeight,
        child: Center(child: Text('Need more history', style: EText.caption)),
      );
    }

    return SizedBox(
      height: widget.chartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotSize = Size(constraints.maxWidth, constraints.maxHeight);
          final plot = CategoryTrendPlot.from(
            size: plotSize,
            seriesList: _visibleSeries,
            housingChain: widget.housingChain,
            jobChain: widget.jobChain,
            lifeEvents: widget.lifeEvents,
          );
          return MouseRegion(
            onHover: (event) {
              _inspect.value = CategoryTrendInspect(
                date: plot.dateForX(event.localPosition.dx),
              );
            },
            onExit: (_) => _inspect.value = null,
            child: GestureDetector(
              onTapUp: widget.enableContributors
                  ? (details) =>
                        _openContributorsAt(details.localPosition, plot)
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      isComplex: true,
                      willChange: false,
                      size: plotSize,
                      painter: CategoryTrendPainter(
                        seriesList: _visibleSeries,
                        lifeEvents: widget.lifeEvents,
                        housingChain: widget.housingChain,
                        jobChain: widget.jobChain,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<CategoryTrendInspect?>(
                    valueListenable: _inspect,
                    builder: (context, inspect, _) => CustomPaint(
                      willChange: inspect != null,
                      size: plotSize,
                      painter: CategoryTrendInspectPainter(
                        plot: plot,
                        inspect: inspect,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _toggleSeries(String seriesId) {
    setState(() {
      if (_hiddenSeriesIds.contains(seriesId)) {
        _hiddenSeriesIds.remove(seriesId);
      } else {
        _hiddenSeriesIds.add(seriesId);
      }
      _visibleSeries = _filterVisibleSeries();
    });
  }

  /// Hide every series except [seriesId]. Double-tap again to restore defaults.
  void _soloSeries(String seriesId) {
    setState(() {
      if (_isSoloed(seriesId)) {
        _hiddenSeriesIds
          ..clear()
          ..addAll(widget.initiallyHiddenSeriesIds);
      } else {
        _hiddenSeriesIds
          ..clear()
          ..addAll(
            widget.seriesList
                .where((series) => series.id != seriesId)
                .map((series) => series.id),
          );
      }
      _visibleSeries = _filterVisibleSeries();
    });
  }

  bool _isSoloed(String seriesId) {
    for (final series in widget.seriesList) {
      final isHidden = _hiddenSeriesIds.contains(series.id);
      if (series.id == seriesId) {
        if (isHidden) return false;
      } else if (!isHidden) {
        return false;
      }
    }
    return true;
  }

  void _openContributorsAt(Offset position, CategoryTrendPlot plot) {
    final tapDate = plot.dateForX(position.dx);
    final series = _nearestVisibleSeries(position, plot, tapDate);
    if (series == null) return;

    final contributors = TrendPointContributors.topForSeries(
      series: series,
      tapDate: tapDate,
      transactions: widget.transactions,
      categories: widget.categories,
      groups: widget.groups,
    );
    if (contributors.isEmpty) return;

    final tapPoint = series.nearestPoint(tapDate);
    if (tapPoint == null) return;

    TrendPointContributorsSheet.show(
      context,
      seriesName: series.name,
      tapDate: tapDate,
      contributors: contributors,
      linePaceCents: tapPoint.smoothedCents.round(),
    );
  }

  CategoryTrendSeries? _nearestVisibleSeries(
    Offset position,
    CategoryTrendPlot plot,
    DateTime tapDate,
  ) {
    if (position.dy < plot.chart.top || position.dy > plot.chart.bottom) {
      return null;
    }

    CategoryTrendSeries? nearestSeries;
    var nearestDistance = double.infinity;
    for (final series in plot.drawableSeries) {
      if (series.guide ||
          series.id == TrendChartCatalog.housingAffordabilitySeriesId ||
          series.id == TrendChartCatalog.fireSavingsGuideSeriesId) {
        continue;
      }
      final point = series.nearestPoint(tapDate);
      if (point == null) continue;
      final seriesY = plot.scale.yForCents(point.smoothedCents, plot.chart);
      final distance = (seriesY - position.dy).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestSeries = series;
      }
    }
    return nearestSeries;
  }
}
