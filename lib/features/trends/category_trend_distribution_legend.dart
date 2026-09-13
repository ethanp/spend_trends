import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/trends/category_trend_distribution.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/distribution_legend_cluster.dart';
import 'package:spend_trends/features/trends/distribution_whisker_painter.dart';
import 'package:spend_trends/features/trends/trend_legend_swatch.dart';
import 'package:spend_trends/features/trends/trend_value_scale.dart';

/// Shared-scale min/med/avg/max/now whiskers for ranked category/group series.
class const CategoryTrendDistributionLegend({
  required final List<CategoryTrendSeries> seriesList,
  required final Set<String> hiddenSeriesIds,
  required final TrendSpendRate spendRate,
  required final ValueChanged<String> onSeriesToggled,
  required final ValueChanged<String> onSeriesSoloed,
  final DateTime? inspectDate,
}) extends StatefulWidget {
  static const whiskerHeight = 240.0;
  static const labelBlockHeight = 66.0;
  static const columnWidth = 96.0;
  static const axisWidth = 44.0;
  static const columnGap = ELayout.spaceSm;
  static const expandDuration = Duration(milliseconds: 280);

  @override
  State<CategoryTrendDistributionLegend> createState() =>
      _CategoryTrendDistributionLegendState();
}

class _CategoryTrendDistributionLegendState()
    extends State<CategoryTrendDistributionLegend> {
  String? _expandedGroupSeriesId;

  @override
  Widget build(BuildContext context) {
    final clusters = DistributionLegendCluster.fromSeries(widget.seriesList);
    final pairsBySeriesId = _pairsBySeriesId();
    final scale = _sharedScale(pairsBySeriesId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DistributionWhiskerSymbolKey(),
        const SizedBox(height: ELayout.spaceSm),
        _whiskerChart(
          clusters: clusters,
          pairsBySeriesId: pairsBySeriesId,
          scale: scale,
        ),
      ],
    );
  }

  Map<String, CategoryTrendDistributionPair> _pairsBySeriesId() {
    final pairsBySeriesId = <String, CategoryTrendDistributionPair>{};
    for (final series in widget.seriesList) {
      var pair = distributionPairForSmoothed(series.points);
      final inspectDay = widget.inspectDate;
      if (inspectDay != null) {
        final inspectPoint = series.nearestPoint(inspectDay);
        if (inspectPoint != null) {
          pair = pair.withCurrentCents(inspectPoint.smoothedCents);
        }
      }
      if (!pair.isEmpty) {
        pairsBySeriesId[series.id] = pair;
      }
    }
    return pairsBySeriesId;
  }

  TrendValueScale _sharedScale(
    Map<String, CategoryTrendDistributionPair> pairsBySeriesId,
  ) {
    var dataMaxCents = 0.0;
    for (final pair in pairsBySeriesId.values) {
      for (final distribution in [pair.allTime, pair.pastYear]) {
        if (distribution == null) continue;
        dataMaxCents = math.max(
          dataMaxCents,
          math.max(distribution.maxCents, distribution.currentCents),
        );
      }
    }
    return TrendValueScale.niceForMax(dataMaxCents);
  }

  Widget _whiskerChart({
    required List<DistributionLegendCluster> clusters,
    required Map<String, CategoryTrendDistributionPair> pairsBySeriesId,
    required TrendValueScale scale,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: CategoryTrendDistributionLegend.axisWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(
                height: CategoryTrendDistributionLegend.labelBlockHeight,
              ),
              _DistributionAxisLabels(
                scale: scale,
                whiskerHeight: CategoryTrendDistributionLegend.whiskerHeight,
                formatTick: _formatAnnualized,
              ),
            ],
          ),
        ),
        const SizedBox(width: ELayout.spaceXs),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Stack(
              children: [
                Positioned(
                  top: CategoryTrendDistributionLegend.labelBlockHeight,
                  left: 0,
                  right: 0,
                  height: CategoryTrendDistributionLegend.whiskerHeight,
                  child: CustomPaint(
                    painter: DistributionWhiskerGridPainter(scale: scale),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      var clusterIndex = 0;
                      clusterIndex < clusters.length;
                      clusterIndex++
                    ) ...[
                      if (clusterIndex > 0)
                        const SizedBox(
                          width: CategoryTrendDistributionLegend.columnGap,
                        ),
                      _clusterColumns(
                        clusters[clusterIndex],
                        pairsBySeriesId: pairsBySeriesId,
                        scale: scale,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _clusterColumns(
    DistributionLegendCluster cluster, {
    required Map<String, CategoryTrendDistributionPair> pairsBySeriesId,
    required TrendValueScale scale,
  }) {
    final isExpanded = _expandedGroupSeriesId == cluster.rollup.id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _seriesColumn(
          cluster.rollup,
          pairsBySeriesId: pairsBySeriesId,
          scale: scale,
          canExpand: cluster.canExpand,
          isExpanded: isExpanded,
        ),
        _expandingMemberColumns(
          cluster,
          pairsBySeriesId: pairsBySeriesId,
          scale: scale,
          isExpanded: isExpanded,
        ),
      ],
    );
  }

  Widget _expandingMemberColumns(
    DistributionLegendCluster cluster, {
    required Map<String, CategoryTrendDistributionPair> pairsBySeriesId,
    required TrendValueScale scale,
    required bool isExpanded,
  }) {
    if (!cluster.canExpand) return const SizedBox.shrink();
    return ClipRect(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: isExpanded ? 1 : 0),
        duration: CategoryTrendDistributionLegend.expandDuration,
        curve: Curves.easeOutCubic,
        builder: (context, widthFactor, child) {
          return Align(
            alignment: Alignment.centerLeft,
            widthFactor: widthFactor,
            child: child,
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final member in cluster.members) ...[
              const SizedBox(width: CategoryTrendDistributionLegend.columnGap),
              _seriesColumn(
                member,
                pairsBySeriesId: pairsBySeriesId,
                scale: scale,
                canExpand: false,
                isExpanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _seriesColumn(
    CategoryTrendSeries series, {
    required Map<String, CategoryTrendDistributionPair> pairsBySeriesId,
    required TrendValueScale scale,
    required bool canExpand,
    required bool isExpanded,
  }) {
    return SizedBox(
      width: CategoryTrendDistributionLegend.columnWidth,
      child: _DistributionColumn(
        series: series,
        pair: pairsBySeriesId[series.id],
        scale: scale,
        isHidden: widget.hiddenSeriesIds.contains(series.id),
        canExpand: canExpand,
        isExpanded: isExpanded,
        formatAnnualized: _formatAnnualized,
        pastYearTotalLabel: _pastYearTotalLabel(series),
        onActivated: () => _activateSeries(series, canExpand: canExpand),
        onSoloActivated: () => widget.onSeriesSoloed(series.id),
      ),
    );
  }

  void _activateSeries(CategoryTrendSeries series, {required bool canExpand}) {
    if (canExpand) {
      setState(() {
        _expandedGroupSeriesId = _expandedGroupSeriesId == series.id
            ? null
            : series.id;
      });
      return;
    }
    widget.onSeriesToggled(series.id);
  }

  String _formatAnnualized(int annualizedCents) {
    return formatCentsWholeDollars(
      widget.spendRate.displayCents(annualizedCents),
    );
  }

  String _pastYearTotalLabel(CategoryTrendSeries series) {
    if (series.points.isEmpty) return '—';
    final totalCents = series.points.last.rollingCents.round();
    if (totalCents <= 0) return '—';
    return formatCentsWholeDollars(totalCents);
  }
}

class const _DistributionAxisLabels({
  required final TrendValueScale scale,
  required final double whiskerHeight,
  required final String Function(int cents) formatTick,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tickStyle = EText.caption.copyWith(fontSize: 10);
    return SizedBox(
      height: whiskerHeight,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final tickCents in scale.tickCents)
            Positioned(
              top: scale.yFromWhiskerBandTop(tickCents, whiskerHeight) - 7,
              right: 0,
              child: Text(
                formatTick(tickCents.round()),
                style: tickStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class const _DistributionColumn({
  required final CategoryTrendSeries series,
  required final CategoryTrendDistributionPair? pair,
  required final TrendValueScale scale,
  required final bool isHidden,
  required final bool canExpand,
  required final bool isExpanded,
  required final String Function(int cents) formatAnnualized,
  required final String pastYearTotalLabel,
  required final VoidCallback onActivated,
  required final VoidCallback onSoloActivated,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final nowCents =
        pair?.pastYear?.currentCents ?? pair?.allTime?.currentCents;
    final nowLabel = nowCents == null
        ? '—'
        : formatAnnualized(nowCents.round());
    final periodLabelStyle = EText.caption.copyWith(
      color: isHidden ? EColors.textMuted : EColors.textMuted,
      fontSize: 9,
      height: 1,
    );

    return GestureDetector(
      onTap: onActivated,
      onDoubleTap: onSoloActivated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: CategoryTrendDistributionLegend.labelBlockHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TrendLegendSwatch(series: series, isHidden: isHidden),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        series.name,
                        style: isHidden
                            ? EText.caption.copyWith(
                                color: EColors.textMuted,
                                fontSize: 11,
                              )
                            : EText.caption.copyWith(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (canExpand)
                      Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: isHidden
                            ? EColors.textMuted
                            : EColors.textSecondary,
                      ),
                  ],
                ),
                Text(
                  nowLabel,
                  style: isHidden
                      ? EText.caption.copyWith(color: EColors.textMuted)
                      : EText.caption.copyWith(color: EColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'all',
                        style: periodLabelStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '1y',
                        style: periodLabelStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    Expanded(
                      child: Text(
                        pastYearTotalLabel,
                        style: isHidden
                            ? EText.caption.copyWith(
                                color: EColors.textMuted,
                                fontSize: 10,
                                height: 1.1,
                              )
                            : EText.caption.copyWith(
                                color: EColors.textSecondary,
                                fontSize: 10,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: CategoryTrendDistributionLegend.whiskerHeight,
            width: double.infinity,
            child: _buildWhiskerPair(),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiskerPair() {
    final distributionPair = pair;
    if (distributionPair == null || distributionPair.isEmpty) {
      return Center(child: Text('—', style: EText.caption));
    }
    return Row(
      children: [
        Expanded(
          child: _DistributionWhisker(
            distribution: distributionPair.allTime,
            scale: scale,
            seriesColor: series.lineColor.withValues(alpha: 0.55),
            isHidden: isHidden,
          ),
        ),
        Expanded(
          child: _DistributionWhisker(
            distribution: distributionPair.pastYear,
            scale: scale,
            seriesColor: series.lineColor,
            isHidden: isHidden,
          ),
        ),
      ],
    );
  }
}

class const _DistributionWhisker({
  required final CategoryTrendDistribution? distribution,
  required final TrendValueScale scale,
  required final Color seriesColor,
  required final bool isHidden,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (distribution == null) {
      return Center(child: Text('—', style: EText.caption));
    }
    return CustomPaint(
      painter: DistributionWhiskerPainter(
        distribution: distribution!,
        scale: scale,
        seriesColor: seriesColor,
        isDimmed: isHidden,
      ),
      child: const SizedBox.expand(),
    );
  }
}
