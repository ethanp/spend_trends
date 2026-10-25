import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/projections/projections_providers.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_card.dart';

import 'trends_providers.dart';

/// The three numbers over 2y · 1y · 6mo against their guidelines. Investments'
/// guideline is what retiring at the planned age needs, once the projection
/// can run (birth year set); Ramit's 10% until then.
class const ConsciousSpendingNumbersCard({
  required final ConsciousSpendingNumbers consciousSpendingNumbers,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastYear = consciousSpendingNumbers.totalsFor(
      ConsciousSpendingWindow.oneYear,
    );
    final RetirementSavingsTarget? retirementTarget = ref
        .watch(retirementProjectionProvider)
        .asData
        ?.value
        .savingsTarget;
    final TrendSpendRate spendRate = ref.watch(trendSpendRateProvider);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'YOUR THREE NUMBERS',
            style: EText.label.small.copyWith(
              color: EColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: ELayout.spaceMd),
          _ConsciousSpendingNumbersTable(
            consciousSpendingNumbers: consciousSpendingNumbers,
            spendRate: spendRate,
            guidelineByArea: {
              for (final area in ConsciousSpendingArea.values)
                area: ConsciousSpendingGuideline.forArea(
                  area,
                  retirementTarget: retirementTarget,
                ),
            },
          ),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            'Plain totals over the ${consciousSpendingNumbers.periodLabel}. '
            'Dollars are ${spendRate.nameAsCapitalizedWords.toLowerCase()}. '
            'Implied range uses the last year’s '
            '${formatCentsWholeDollars(lastYear.takeHomeCents)} take-home pay.',
            style: EText.caption,
          ),
          if (retirementTarget != null) ...[
            const SizedBox(height: ELayout.spaceXs),
            Text(
              _retirementTargetCaption(retirementTarget, spendRate),
              style: EText.caption,
            ),
          ],
        ],
      ),
    );
  }

  String _retirementTargetCaption(
    RetirementSavingsTarget target,
    TrendSpendRate spendRate,
  ) {
    final spending = formatCentsWholeDollars(
      spendRate.displayCents(
        (target.maxNonHousingSpendingAnnual * 100).round(),
      ),
    );
    final investing = formatCentsWholeDollars(
      spendRate.displayCents(
        (target.requiredInvestingAnnual.clamp(0, double.infinity) * 100)
            .round(),
      ),
    );
    return 'Investments target: retiring at ${target.retirementAge} (Projections) '
        'allows up to $spending/${spendRate.toggleLabel} outside housing, which '
        'leaves $investing/${spendRate.toggleLabel} to invest.';
  }
}

class const _ConsciousSpendingNumbersTable({
  required final ConsciousSpendingNumbers consciousSpendingNumbers,
  required final TrendSpendRate spendRate,
  required final Map<ConsciousSpendingArea, ConsciousSpendingGuideline>
  guidelineByArea,
}) extends StatelessWidget {
  static const _windows = ConsciousSpendingWindow.values;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.7),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(2.4),
        3: FlexColumnWidth(1.6),
        4: FlexColumnWidth(3.2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.bottom,
      children: [
        TableRow(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: EColors.border)),
          ),
          children: [
            _header('Aspect Name', align: TextAlign.left),
            _header('Guideline %'),
            _windowedHeader('Actual %'),
            _header('Implied \$ (1y)'),
            _windowedHeader('Actual \$/${spendRate.toggleLabel}'),
          ],
        ),
        for (final area in ConsciousSpendingArea.values) _areaRow(area),
      ],
    );
  }

  TableRow _areaRow(ConsciousSpendingArea area) {
    final guideline = guidelineByArea[area]!;
    final lastYear = consciousSpendingNumbers.totalsFor(
      ConsciousSpendingWindow.oneYear,
    );
    return TableRow(
      children: [
        _cell(
          area.displayName,
          align: TextAlign.left,
          color: area.color,
          fontWeight: FontWeight.w700,
        ),
        _cell(guideline.rangeLabel),
        _windowedCell([
          for (final window in _windows)
            _actualPercent(
              consciousSpendingNumbers.totalsFor(window),
              area,
              guideline,
            ),
        ]),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: _cell(
            guideline.impliedTakeHomeLabel(
              spendRate.displayCents(lastYear.takeHomeCents),
            ),
          ),
        ),
        _windowedCell([
          for (final window in _windows)
            _cell(
              formatCentsWholeDollars(
                spendRate.displayCents(
                  consciousSpendingNumbers.totalsFor(window).annualCents(area),
                ),
              ),
              rightPadding: 0,
            ),
        ]),
      ],
    );
  }

  Widget _actualPercent(
    ConsciousSpendingWindowTotals totals,
    ConsciousSpendingArea area,
    ConsciousSpendingGuideline guideline,
  ) {
    final int? percent = totals.percentOfTakeHome(area);
    if (percent == null) return _cell('—', rightPadding: 0);
    return _cell(
      '$percent%',
      color: _colorForGuidelineScore(guideline.score(percent)),
      fontWeight: FontWeight.w700,
      rightPadding: 0,
    );
  }

  /// White on the guideline, shading to green as it is beaten and to red as
  /// it is missed.
  static Color _colorForGuidelineScore(double score) {
    if (score >= 0) {
      return Color.lerp(EColors.textPrimary, EColors.success, score)!;
    }
    return Color.lerp(EColors.textPrimary, EColors.danger, -score)!;
  }

  /// Column title over one aligned sub-column per window (2y · 1y · 6mo).
  Widget _windowedHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(title),
        _windowedCell([
          for (final window in _windows) _header(window.label, rightPadding: 0),
        ]),
      ],
    );
  }

  Widget _windowedCell(List<Widget> perWindow) {
    return Padding(
      padding: const EdgeInsets.only(right: ELayout.spaceSm),
      child: Row(
        children: [
          for (var index = 0; index < perWindow.length; index++) ...[
            if (index > 0) const SizedBox(width: ELayout.spaceXs),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: perWindow[index],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(
    String label, {
    TextAlign align = TextAlign.right,
    double rightPadding = ELayout.spaceSm,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: rightPadding, bottom: ELayout.spaceXs),
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
    double rightPadding = ELayout.spaceSm,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        right: rightPadding,
        top: ELayout.spaceXs,
        bottom: ELayout.spaceXs,
      ),
      child: Text(
        label,
        textAlign: align,
        maxLines: 1,
        style: EText.caption.copyWith(
          color: color ?? EColors.textPrimary,
          fontWeight: fontWeight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
