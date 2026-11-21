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
import 'package:spend_trends/ui/trends/where_pay_went_tile.dart';

/// The three numbers over 2y · 1y · 6mo against their guidelines, dollars
/// always as a month over a year. Investments' guideline is what retiring at
/// the planned age needs, once the projection can run (birth year set);
/// Ramit's 10% until then. Null [consciousSpendingNumbers] (still computing)
/// keeps the card's full shape with dashes, so the numbers land without a jump.
///
/// Where pay went leads as donuts, then each area is a tile; tiles reflow
/// into balanced rows with the card's width and their type grows with the
/// tile.
class const ConsciousSpendingNumbersCard({
  required final ConsciousSpendingNumbers? consciousSpendingNumbers,
}) extends ConsumerWidget {
  static const _tileTypeScale = EWidthScaledTypeBounds(
    referenceWidth: 360,
    maxScale: 1.6,
  );

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
          const SizedBox(height: ELayout.spaceMd),
          EBalancedRowsTileGrid(
            minTileWidth: 260,
            gutter: ELayout.spaceMd,
            tileTypeScale: _tileTypeScale,
            sideBySideTileSurface: ESurfaceKind.inset,
            tiles: [
              WherePayWentTile(
                consciousSpendingNumbers: consciousSpendingNumbers,
              ),
              ..._numberTiles(retirementTarget),
            ],
            trailing: _captions(retirementTarget),
          ),
        ],
      ),
    );
  }

  /// One per area, then spending excluded from lifestyle costs, then Savings
  /// (what is left).
  List<Widget> _numberTiles(RetirementSavingsTarget? retirementTarget) {
    return [
      for (final area in ConsciousSpendingArea.values)
        _ConsciousSpendingNumberTile(
          consciousSpendingNumbers: consciousSpendingNumbers,
          name: area.displayName,
          color: area.color,
          guideline: ConsciousSpendingGuideline.forArea(
            area,
            retirementTarget: retirementTarget,
          ),
          isFirst: area == ConsciousSpendingArea.values.first,
          percentOfPay: (totals) => totals.percentOfPay(area),
          annualCents: (totals) => totals.annualCents(area),
        ),
      _ConsciousSpendingNumberTile(
        consciousSpendingNumbers: consciousSpendingNumbers,
        name: 'Excluded from lifestyle',
        color: FinanceColors.excludedFromLifestyleCosts,
        percentOfPay: (totals) => totals.excludedFromLifestylePercentOfPay,
        annualCents: (totals) => totals.annualExcludedFromLifestyleCents,
      ),
      _ConsciousSpendingNumberTile(
        consciousSpendingNumbers: consciousSpendingNumbers,
        name: 'Savings',
        color: FinanceColors.savings,
        guideline: ConsciousSpendingGuideline.savings,
        percentOfPay: (totals) => totals.savingsPercentOfPay,
        annualCents: (totals) => totals.annualSavingsCents,
      ),
    ];
  }

  /// Side by side when both fit at a readable measure; stacked otherwise.
  /// Beside tiles (in the grid's short last row) or below inset tiles, the
  /// text lines up with the tiles' own padding.
  Widget _captions(RetirementSavingsTarget? retirementTarget) {
    return Builder(
      builder: (context) => Padding(
        padding: EBalancedRowsTileGrid.columnCountOf(context) > 1
            ? const EdgeInsets.all(ELayout.spaceMd)
            : const EdgeInsets.only(top: ELayout.spaceSm),
        child: Wrap(
          spacing: ELayout.spaceXl,
          runSpacing: ELayout.spaceSm,
          children: [
            if (retirementTarget != null)
              EReadableMeasure(
                child: Text(
                  _retirementTargetCaption(retirementTarget),
                  style: EText.body.small.copyWith(
                    color: EColors.textSecondary,
                  ),
                ),
              ),
            EReadableMeasure(
              child: Text(_readingKeyCaption, style: EText.caption),
            ),
          ],
        ),
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

  /// How fresh the numbers are, how to read their colors, and the
  /// definitions that change what a number means.
  String get _readingKeyCaption {
    final String throughPhrase = consciousSpendingNumbers == null
        ? 'Computing'
        : 'Through ${DateFormat.MMMd().format(consciousSpendingNumbers!.lastDay)}';
    return '$throughPhrase. Green beats the guideline, red misses it. Pay '
        'includes payroll contributions. Mortgage principal is Investments. '
        'Excluded is one-offs like a closing, kept out of lifestyle costs and '
        'the FIRE projection. Savings is what is left; negative means cash '
        'was drawn down.';
  }

  static String _perMonthPhrase(int annualCents) =>
      '${formatCentsWholeDollars((annualCents / 12).round())}/mo';
}

/// One small multiple: the name and its guideline, then 2y · 1y · 6mo of
/// share of pay (the figure to read first), actual dollars, and the
/// guideline's dollars on that window's pay. Dollar cells stack the month
/// over the year. Color marks only how far each share sits from its
/// guideline. A null [guideline] (excluded spending) has no target row and
/// no color.
///
/// Alone in a row (a phone), only the first repeats the window header; side
/// by side, each tile has its own.
class const _ConsciousSpendingNumberTile({
  required final ConsciousSpendingNumbers? consciousSpendingNumbers,
  required final String name,
  required final Color color,
  final ConsciousSpendingGuideline? guideline,
  final bool isFirst = false,
  required final int? Function(ConsciousSpendingWindowTotals totals)
  percentOfPay,
  required final int? Function(ConsciousSpendingWindowTotals totals)
  annualCents,
}) extends StatelessWidget {
  static const _rowLabels = ['of pay', 'actual', 'target'];

  @override
  Widget build(BuildContext context) {
    final _TileTypeRamp typeRamp = _TileTypeRamp(EWidthScaledType.of(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: ELayout.spaceXs,
      children: [
        _heading(typeRamp),
        _figures(
          typeRamp,
          showColumnHeaders:
              isFirst || EBalancedRowsTileGrid.columnCountOf(context) > 1,
        ),
      ],
    );
  }

  Widget _heading(_TileTypeRamp typeRamp) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: name,
            style: typeRamp.heading.copyWith(color: color),
          ),
          if (guideline != null)
            TextSpan(
              text: '  ${guideline!.boundedTargetLabel}',
              style: typeRamp.label,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _figures(_TileTypeRamp typeRamp, {required bool showColumnHeaders}) {
    const windows = ConsciousSpendingWindow.values;
    return EAlignedFigureColumns(
      labelStyle: typeRamp.label,
      labelsToAlignWith: _rowLabels,
      maxFigureColumnWidth: 96,
      columnHeaders: showColumnHeaders
          ? windows.mapL((window) => window.label)
          : const [],
      rows: [
        EFigureRow(
          label: 'of pay',
          figures: windows.mapL(
            (window) => _percentFigure(typeRamp, _totalsFor(window)),
          ),
        ),
        EFigureRow(
          label: 'actual',
          figures: windows.mapL(
            (window) => _monthOverYearFigure(
              typeRamp,
              _actualAnnualCents(window),
              monthStyle: typeRamp.dollars,
            ),
          ),
        ),
        if (guideline != null && guideline!.targetPercent > 0)
          EFigureRow(
            label: 'target',
            figures: windows.mapL(
              (window) => _monthOverYearFigure(
                typeRamp,
                _targetAnnualCents(window),
                monthStyle: typeRamp.targetDollars,
              ),
            ),
          ),
      ],
    );
  }

  ConsciousSpendingWindowTotals? _totalsFor(ConsciousSpendingWindow window) =>
      consciousSpendingNumbers?.totalsFor(window);

  int? _actualAnnualCents(ConsciousSpendingWindow window) {
    final ConsciousSpendingWindowTotals? totals = _totalsFor(window);
    if (totals == null) return null;
    return annualCents(totals);
  }

  /// The guideline's dollars on that window's pay.
  int? _targetAnnualCents(ConsciousSpendingWindow window) {
    final ConsciousSpendingWindowTotals? totals = _totalsFor(window);
    if (totals == null) return null;
    return guideline!.impliedCents(totals.annualPayCents);
  }

  Widget _percentFigure(
    _TileTypeRamp typeRamp,
    ConsciousSpendingWindowTotals? totals,
  ) {
    final int? percent = totals == null ? null : percentOfPay(totals);
    if (percent == null) return Text('—', style: typeRamp.percent);
    return Text(
      '${percent < 0 ? '−${-percent}' : percent}%',
      style: typeRamp.percent.copyWith(
        color: guideline == null
            ? EColors.textPrimary
            : _colorForGuidelineScore(guideline!.score(percent)),
      ),
    );
  }

  /// The month's dollars, with the year's beneath in muted small type. Null
  /// (still computing) keeps both lines as dashes.
  Widget _monthOverYearFigure(
    _TileTypeRamp typeRamp,
    int? annualCents, {
    required TextStyle monthStyle,
  }) {
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
              TextSpan(text: ' /mo', style: typeRamp.unit),
            ],
          ),
        ),
        Text(
          '${annualCents == null ? '—' : _signedWholeDollars(annualCents)} /yr',
          style: typeRamp.unit,
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

  /// White on the guideline, shading to green as it is beaten and to red as
  /// it is missed.
  static Color _colorForGuidelineScore(double score) {
    if (score >= 0) {
      return Color.lerp(EColors.textPrimary, EColors.success, score)!;
    }
    return Color.lerp(EColors.textPrimary, EColors.danger, -score)!;
  }
}

/// The tile's styles at its width: share of pay leads, actual dollars next,
/// target dollars and units muted.
class _TileTypeRamp(final EWidthTypeScale typeScale) {
  static const _tabularFigures = [FontFeature.tabularFigures()];

  late final TextStyle heading = typeScale.apply(
    EText.body.medium.copyWith(fontWeight: FontWeight.w700),
  );

  late final TextStyle label = typeScale.apply(
    EText.caption.copyWith(color: EColors.textMuted),
  );

  late final TextStyle percent = typeScale.apply(
    EText.body.large.copyWith(
      color: EColors.textPrimary,
      fontWeight: FontWeight.w700,
      height: 1.25,
      fontFeatures: _tabularFigures,
    ),
  );

  late final TextStyle dollars = typeScale.apply(
    EText.body.small.copyWith(
      color: EColors.textPrimary,
      fontFeatures: _tabularFigures,
    ),
  );

  late final TextStyle targetDollars = dollars.copyWith(
    color: EColors.textMuted,
  );

  late final TextStyle unit = typeScale.apply(
    EText.body.tiny.copyWith(
      color: EColors.textMuted,
      fontFeatures: _tabularFigures,
    ),
  );
}
