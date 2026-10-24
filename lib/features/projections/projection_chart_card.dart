import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/domain/projection/projection_tax_treatment.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_card.dart';

/// Liquid savings by tax type and home equity, year by year, with the
/// planned and earliest retirement ages marked.
class const ProjectionChartCard({
  required final RetirementProjection projection,
}) extends StatelessWidget {
  static const _chartHeight = 320.0;
  static const _earliestRetirementColor = EColors.success;
  static const _plannedRetirementColor = EColors.warning;

  @override
  Widget build(BuildContext context) {
    final lines = _lines();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Savings by year (millions, today’s dollars)',
            style: EText.section,
          ),
          const SizedBox(height: ELayout.spaceMd),
          SizedBox(height: _chartHeight, child: _chart(lines)),
          const SizedBox(height: ELayout.spaceMd),
          EChartLegend(entries: [for (final line in lines) _legendEntry(line)]),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            'Gold line: planned retirement · green line: earliest. '
            'Values at the planned age.',
            style: EText.caption,
          ),
        ],
      ),
    );
  }

  List<_ProjectionLine> _lines() => [
    _ProjectionLine(
      id: 'liquid',
      label: 'Liquid total',
      color: TrendChartCatalog.netWorthLineColor,
      valueOf: (year) => year.liquid,
    ),
    for (final treatment in [
      ProjectionTaxTreatment.taxable,
      ProjectionTaxTreatment.traditional,
      ProjectionTaxTreatment.roth,
    ])
      _ProjectionLine(
        id: treatment.name,
        label: treatment.label,
        color: treatment.color,
        valueOf: (year) => switch (treatment) {
          ProjectionTaxTreatment.taxable => year.taxable,
          ProjectionTaxTreatment.traditional => year.traditional,
          _ => year.roth,
        },
      ),
    _ProjectionLine(
      id: 'home',
      label: 'Home equity',
      color: OwnedAssetKind.home.lineColor,
      valueOf: (year) => year.homeEquity,
      dash: EChartStrokeDash.dotted,
    ),
  ];

  Widget _chart(List<_ProjectionLine> lines) {
    final years = projection.years;
    final double peakMillions =
        years
            .map(
              (year) =>
                  lines.map((line) => line.valueOf(year)).reduce(math.max),
            )
            .reduce(math.max) /
        1e6;
    return EChart<int>(
      start: DateTime(years.first.year),
      end: DateTime(years.last.year),
      valueScale: EChartValueScale.nice(peakMillions, tickSuffix: 'M'),
      series: [
        for (final line in lines)
          EChartSeries<int>.line(
            id: line.id,
            color: line.color,
            dash: line.dash,
            strokeWidth: line.id == 'liquid' ? 2 : 1.2,
            hits: EChartPointHits.ignore,
            points: [
              for (final year in years)
                EChartPoint<int>(
                  date: DateTime(year.year),
                  value: math.max(0, line.valueOf(year)) / 1e6,
                  id: year.age,
                ),
            ],
          ),
      ],
      annotations: [
        _RetirementYearMarker(
          date: _dateAtAge(projection.assumptions.retirementAge),
          color: _plannedRetirementColor,
        ),
        if (projection.earliestRetirementAge != null)
          _RetirementYearMarker(
            date: _dateAtAge(projection.earliestRetirementAge!),
            color: _earliestRetirementColor,
          ),
      ],
    );
  }

  DateTime _dateAtAge(int age) =>
      DateTime(projection.start.today.year + age - projection.currentAge!);

  EChartLegendEntry _legendEntry(_ProjectionLine line) {
    final atRetirement = projection.years
        .where((year) => year.age == projection.assumptions.retirementAge)
        .firstOrNull;
    return EChartLegendEntry(
      swatch: Container(width: 10, height: 10, color: line.color),
      label: line.label,
      value: atRetirement == null
          ? null
          : formatCentsWholeDollars((line.valueOf(atRetirement) * 100).round()),
    );
  }
}

class const _ProjectionLine({
  required final String id,
  required final String label,
  required final Color color,
  required final double Function(ProjectionYear year) valueOf,
  final EChartStrokeDash dash = EChartStrokeDash.solid,
});

/// A vertical rule at a retirement year.
class _RetirementYearMarker({
  required final DateTime date,
  required final Color color,
}) extends EChartAnnotation {
  @override
  void paint(Canvas canvas, EChartPlot plot) {
    final x = plot.xForDate(date);
    canvas.drawLine(
      Offset(x, plot.top),
      Offset(x, plot.bottom),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
  }
}
