import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_card.dart';

class const FourNumbersCard({
  final List<CategoryTrendSeries> cashFlows = const [],
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'YOUR FOUR NUMBERS',
            style: EText.label.small.copyWith(
              color: EColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: ELayout.spaceMd),
          _FourNumbersTable(cashFlows: cashFlows),
          const SizedBox(height: ELayout.spaceSm),
          Text('Annual pace of take-home pay.', style: EText.caption),
        ],
      ),
    );
  }
}

class const _FourNumbersTable({
  required final List<CategoryTrendSeries> cashFlows,
}) extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.1),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1.7),
        4: FlexColumnWidth(1.1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: EColors.border)),
          ),
          children: [
            _header('Aspect Name', align: TextAlign.left),
            _header('Guideline % range'),
            _header('Actual %'),
            _header('Implied \$ range'),
            _header('Actual \$'),
          ],
        ),
        for (final area in ConsciousSpendingArea.values)
          _areaRow(area),
      ],
    );
  }

  TableRow _areaRow(ConsciousSpendingArea area) {
    final incomeCents = _smoothedCents(TrendChartCatalog.incomeSeriesId);
    final areaCents = _smoothedCents(
      TrendChartCatalog.consciousSpendingAreaSeriesId(area),
    );
    final percent = area.percentOfIncome(
      areaCents: areaCents,
      incomeCents: incomeCents,
    );
    final offGuideline = percent != null && !area.containsPercent(percent);
    return TableRow(
      children: [
        _cell(
          area.displayName,
          align: TextAlign.left,
          color: area.color,
          fontWeight: FontWeight.w700,
        ),
        _cell(area.targetRangeLabel),
        _cell(
          percent == null ? '—' : '$percent%',
          color: offGuideline ? EColors.warning : EColors.textPrimary,
        ),
        _cell(area.impliedTakeHomeLabel(incomeCents)),
        _cell(formatCentsWholeDollars(areaCents)),
      ],
    );
  }

  int _smoothedCents(String seriesId) {
    for (final series in cashFlows) {
      if (series.id == seriesId) return series.latestSmoothedCents.round();
    }
    return 0;
  }

  Widget _header(String label, {TextAlign align = TextAlign.right}) {
    return Padding(
      padding: const EdgeInsets.only(
        right: ELayout.spaceSm,
        bottom: ELayout.spaceXs,
      ),
      child: Text(
        label,
        textAlign: align,
        style: EText.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: EColors.textMuted,
        ),
      ),
    );
  }

  Widget _cell(
    String label, {
    TextAlign align = TextAlign.right,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        right: ELayout.spaceSm,
        top: ELayout.spaceXs,
        bottom: ELayout.spaceXs,
      ),
      child: Text(
        label,
        textAlign: align,
        style: EText.caption.copyWith(
          color: color ?? EColors.textPrimary,
          fontWeight: fontWeight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
