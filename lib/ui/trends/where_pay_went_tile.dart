import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/categories/conscious_spending_numbers.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';

/// Where pay went over 2y · 1y · 6mo, one donut per window, sliced by the
/// three areas, excluded spending, and what was saved. A window that drew
/// cash down has no savings slice and says how much past pay it spent. Null
/// [consciousSpendingNumbers] (still computing) shows empty rings, so the
/// tile keeps its shape. The area tiles' colored headings name the slices.
class const WherePayWentTile({
  required final ConsciousSpendingNumbers? consciousSpendingNumbers,
}) extends StatelessWidget {
  static const _maxDonutDiameter = 112.0;

  @override
  Widget build(BuildContext context) {
    final EWidthTypeScale typeScale = EWidthScaledType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: ELayout.spaceSm,
      children: [
        Text(
          'Where pay went',
          style: typeScale.apply(
            EText.body.medium.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: ELayout.spaceSm,
          children: ConsciousSpendingWindow.values.mapL(
            (window) => Expanded(
              child: _windowDonut(
                typeScale,
                window,
                consciousSpendingNumbers?.totalsFor(window),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The ring with its window inside, pay (or the draw-down) beneath.
  Widget _windowDonut(
    EWidthTypeScale typeScale,
    ConsciousSpendingWindow window,
    ConsciousSpendingWindowTotals? totals,
  ) {
    final TextStyle labelStyle = typeScale.apply(
      EText.caption.copyWith(color: EColors.textMuted),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: ELayout.spaceXs,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: typeScale.length(_maxDonutDiameter * ELayout.typeScale),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                EDonut(
                  slices: _slices(totals),
                  thickness: typeScale.length(11 * ELayout.typeScale),
                  gapRadians: 0.05,
                ),
                Text(
                  window.label,
                  style: typeScale.apply(
                    EText.body.medium.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: _payCaption(typeScale, totals, labelStyle: labelStyle),
        ),
      ],
    );
  }

  /// Average pay per month; beneath it, when spending passed pay, how far
  /// past, tinted red by how far it misses Savings' guideline.
  Widget _payCaption(
    EWidthTypeScale typeScale,
    ConsciousSpendingWindowTotals? totals, {
    required TextStyle labelStyle,
  }) {
    if (totals == null) return Text('— /mo pay', style: labelStyle);
    final int? savingsPercent = totals.savingsPercentOfPay;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${formatCentsWholeDollars((totals.annualPayCents / 12).round())}/mo pay',
          style: labelStyle.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (savingsPercent != null && savingsPercent < 0)
          Text(
            'spent ${100 - savingsPercent}%',
            style: labelStyle.copyWith(
              color: ConsciousSpendingGuideline.savings.colorForPercent(
                savingsPercent,
                onTarget: labelStyle.color!,
              ),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }

  /// Same order as the tiles beside it.
  List<EDonutSlice> _slices(ConsciousSpendingWindowTotals? totals) {
    if (totals == null) {
      return const [EDonutSlice(value: 1, color: EColors.surfaceRaised)];
    }
    return [
      for (final area in ConsciousSpendingArea.values)
        EDonutSlice(
          value: totals.centsByArea[area]!.toDouble(),
          color: area.color,
        ),
      EDonutSlice(
        value: totals.excludedFromLifestyleCents.toDouble(),
        color: FinanceColors.excludedFromLifestyleCosts,
      ),
      if (totals.savingsCents > 0)
        EDonutSlice(
          value: totals.savingsCents.toDouble(),
          color: FinanceColors.savings,
        ),
    ].whereL((slice) => slice.value > 0);
  }
}
