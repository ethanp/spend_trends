import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/ui/projections/projections_providers.dart';
import 'package:spend_trends/domain/categories/conscious_spending_numbers.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';

/// The three numbers over 2y · 1y · 6mo against their guidelines, dollars
/// always as a month over a year. Investments' guideline is what retiring at
/// the planned age needs, once the projection can run (birth year set);
/// Ramit's 10% until then. Null [consciousSpendingNumbers] (still computing)
/// keeps the card's full shape with dashes, so the numbers land without a jump.
class const ConsciousSpendingNumbersCard({
  required final ConsciousSpendingNumbers? consciousSpendingNumbers,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RetirementSavingsTarget? retirementTarget = ref
        .watch(retirementProjectionProvider)
        .asData
        ?.value
        .savingsTarget;
    return ECard(
      kind: ESurfaceKind.row,
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
          const SizedBox(height: ELayout.spaceSm),
          _ConsciousSpendingNumbersGrid(
            consciousSpendingNumbers: consciousSpendingNumbers,
            guidelineByArea: {
              for (final area in ConsciousSpendingArea.values)
                area: ConsciousSpendingGuideline.forArea(
                  area,
                  retirementTarget: retirementTarget,
                ),
            },
          ),
          if (retirementTarget != null) ...[
            const SizedBox(height: ELayout.spaceMd),
            Text(
              _retirementTargetCaption(retirementTarget),
              style: EText.body.small.copyWith(color: EColors.textSecondary),
            ),
          ],
          const SizedBox(height: ELayout.spaceSm),
          Text(_readingKeyCaption, style: EText.caption),
        ],
      ),
    );
  }

  /// What to change to retire as planned, in this month's terms.
  String _retirementTargetCaption(RetirementSavingsTarget target) {
    final String spendingCap = _perMonthPhrase(
      (target.maxNonHousingSpendingAnnual * 100).round(),
    );
    final String investing = _perMonthPhrase(
      (target.requiredInvestingAnnual.clamp(0, double.infinity) * 100).round(),
    );
    return 'To retire at ${target.retirementAge} as planned: spend at most '
        '$spendingCap outside housing and invest $investing, mortgage '
        'principal included.';
  }

  /// How fresh the grid is, how to read its colors, and the definitions that
  /// change what a number means.
  String get _readingKeyCaption {
    final String throughPhrase = consciousSpendingNumbers == null
        ? 'Computing'
        : 'Through ${DateFormat.MMMd().format(consciousSpendingNumbers!.lastDay)}';
    return '$throughPhrase. Green beats the guideline, red misses it. Pay '
        'includes payroll contributions. Mortgage principal is Investments. '
        'Excluded is one-offs like a closing, kept out of the FIRE '
        'projection. Savings is what is left; negative means cash was '
        'drawn down.';
  }

  static String _perMonthPhrase(int annualCents) =>
      '${formatCentsWholeDollars((annualCents / 12).round())}/mo';
}

/// Small multiples: one block per area, spending excluded from lifestyle
/// costs, then Savings (what is left), with the
/// same 2y · 1y · 6mo columns: share of pay, actual dollars, and the
/// guideline's dollars on that window's pay. Dollar cells stack the month over
/// the year. The guideline percent sits beside the name, so the grid needs
/// only a row label plus one column per window and fits a phone. Color marks
/// only how far each share sits from its guideline.
class const _ConsciousSpendingNumbersGrid({
  required final ConsciousSpendingNumbers? consciousSpendingNumbers,
  required final Map<ConsciousSpendingArea, ConsciousSpendingGuideline>
  guidelineByArea,
}) extends StatelessWidget {
  static const _windows = ConsciousSpendingWindow.values;
  static const _rowLabelFlex = 2;
  static const _windowFlex = 3;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _gridRow(
          rowLabel: '',
          windowCells: [
            for (final window in _windows)
              Text(window.label, style: _labelStyle),
          ],
        ),
        for (final area in ConsciousSpendingArea.values)
          _numberBlock(
            name: area.displayName,
            color: area.color,
            guideline: guidelineByArea[area]!,
            percentOfPay: (totals) => totals?.percentOfPay(area),
            annualCents: (totals) => totals?.annualCents(area),
          ),
        _numberBlock(
          name: 'Excluded from lifestyle costs',
          color: FinanceColors.excludedFromLifestyleCosts,
          percentOfPay: (totals) => totals?.excludedFromLifestylePercentOfPay,
          annualCents: (totals) => totals?.annualExcludedFromLifestyleCents,
        ),
        _numberBlock(
          name: 'Savings',
          color: FinanceColors.savings,
          guideline: ConsciousSpendingGuideline.savings,
          percentOfPay: (totals) => totals?.savingsPercentOfPay,
          annualCents: (totals) => totals?.annualSavingsCents,
        ),
      ],
    );
  }

  /// A null [guideline] (excluded spending) has no target: no target row,
  /// no color. The figure readers get null totals while the numbers compute.
  Widget _numberBlock({
    required String name,
    required Color color,
    ConsciousSpendingGuideline? guideline,
    required int? Function(ConsciousSpendingWindowTotals?) percentOfPay,
    required int? Function(ConsciousSpendingWindowTotals?) annualCents,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: ELayout.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: ELayout.spaceXs,
        children: [
          _blockHeading(name: name, color: color, guideline: guideline),
          _gridRow(
            rowLabel: 'of pay',
            windowCells: [
              for (final window in _windows)
                _percentCell(
                  percentOfPay(consciousSpendingNumbers?.totalsFor(window)),
                  guideline,
                ),
            ],
          ),
          _gridRow(
            rowLabel: 'actual',
            windowCells: [
              for (final window in _windows)
                _monthOverYearCell(
                  annualCents(consciousSpendingNumbers?.totalsFor(window)),
                  monthStyle: _valueStyle,
                ),
            ],
          ),
          if (guideline != null)
            _gridRow(
              rowLabel: 'target',
              windowCells: [
                for (final window in _windows)
                  _monthOverYearCell(
                    _impliedTargetCents(guideline, window),
                    monthStyle: _labelStyle,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  int? _impliedTargetCents(
    ConsciousSpendingGuideline guideline,
    ConsciousSpendingWindow window,
  ) {
    final ConsciousSpendingWindowTotals? totals = consciousSpendingNumbers
        ?.totalsFor(window);
    if (totals == null) return null;
    return guideline.impliedCents(totals.annualPayCents);
  }

  /// Block name, then its guideline percent when it has one.
  Widget _blockHeading({
    required String name,
    required Color color,
    required ConsciousSpendingGuideline? guideline,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: name,
            style: EText.body.medium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (guideline != null)
            TextSpan(text: '   ${guideline.targetLabel}', style: _labelStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// The month's dollars, with the year's beneath in muted caption. Null
  /// (still computing) keeps both lines as dashes.
  Widget _monthOverYearCell(int? annualCents, {required TextStyle monthStyle}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: annualCents == null
                    ? '—'
                    : _signedWholeDollars((annualCents / 12).round()),
                style: monthStyle,
              ),
              TextSpan(text: ' /mo', style: _unitStyle),
            ],
          ),
        ),
        Text(
          '${annualCents == null ? '—' : _signedWholeDollars(annualCents)} /yr',
          style: _unitStyle,
        ),
      ],
    );
  }

  /// `−$2.3k` for a draw-down; the shared formatter only handles the sign
  /// for small amounts.
  static String _signedWholeDollars(int cents) {
    if (cents < 0) return '−${formatCentsWholeDollars(-cents)}';
    return formatCentsWholeDollars(cents);
  }

  Widget _gridRow({
    required String rowLabel,
    required List<Widget> windowCells,
  }) {
    return Row(
      children: [
        Expanded(
          flex: _rowLabelFlex,
          child: Text(rowLabel, style: _labelStyle, maxLines: 1),
        ),
        for (final windowCell in windowCells)
          Expanded(
            flex: _windowFlex,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: windowCell),
            ),
          ),
      ],
    );
  }

  Widget _percentCell(int? percent, ConsciousSpendingGuideline? guideline) {
    if (percent == null) return Text('—', style: _valueStyle);
    return Text(
      '$percent%',
      style: _valueStyle.copyWith(
        color: guideline == null
            ? EColors.textPrimary
            : _colorForGuidelineScore(guideline.score(percent)),
        fontWeight: FontWeight.w700,
      ),
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

  static final TextStyle _labelStyle = EText.caption.copyWith(
    color: EColors.textMuted,
  );

  static final TextStyle _unitStyle = EText.caption.copyWith(
    color: EColors.textMuted,
    fontSize: 10,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static final TextStyle _valueStyle = EText.body.small.copyWith(
    color: EColors.textPrimary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
