import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/domain/projection/roth_conversion_comparison.dart';
import 'package:spend_trends/use_cases/projection/projection_assumptions_editor.dart';

/// Each Roth conversion choice on the same plan: lifetime tax, what heirs
/// keep at the end age, and the earliest retirement age. Choosing a row
/// saves it.
class const RothConversionCard({required final RetirementProjection projection})
    extends ConsumerWidget {
  static const _choiceWidth = 72.0;
  static const _figureWidth = 104.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RothConversionOutcome> outcomes = RothConversionComparison(
      projection,
    ).outcomes;
    return ECard(
      kind: ESurfaceKind.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Roth conversions', style: EText.section),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            'Each retired year, traditional money fills ordinary income to '
            'the top of the bracket; what spending does not use converts '
            'to Roth (before 59½, all of it). Heirs pay tax on traditional '
            'over ten years; taxable and Roth pass free. Lifetime tax is '
            'discounted at the real return, since tax paid early also costs '
            'its growth. Today’s dollars.',
            style: EText.caption,
          ),
          const SizedBox(height: ELayout.spaceSm),
          _headerRow(),
          for (final outcome in outcomes) _outcomeRow(ref, outcome),
        ],
      ),
    );
  }

  Widget _headerRow() => _columns(
    choice: 'Convert',
    lifetimeTaxes: 'Lifetime tax (PV)',
    leftToHeirs: 'Heirs keep at ${projection.assumptions.endAge}',
    earliestAge: 'Earliest',
    style: EText.caption.copyWith(color: EColors.textMuted),
  );

  Widget _outcomeRow(WidgetRef ref, RothConversionOutcome outcome) {
    final bool isChosen =
        outcome.bracketPercent ==
        projection.assumptions.rothConversionBracketPercent;
    return InkWell(
      onTap: isChosen
          ? null
          : () => ref.read(projectionAssumptionsEditorProvider).apply({
              'rothConversionBracketPercent': outcome.bracketPercent,
            }),
      child: Container(
        color: isChosen ? EColors.accentSoft : null,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: _columns(
          choice: outcome.label,
          lifetimeTaxes: formatCentsWholeDollars(
            (outcome.lifetimeTaxesPresentValue * 100).round(),
          ),
          leftToHeirs: formatCentsWholeDollars(
            (outcome.leftToHeirs * 100).round(),
          ),
          earliestAge: '${outcome.earliestRetirementAge ?? '—'}',
          style: EText.caption.copyWith(
            color: EColors.textPrimary,
            fontWeight: isChosen ? FontWeight.w700 : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _columns({
    required String choice,
    required String lifetimeTaxes,
    required String leftToHeirs,
    required String earliestAge,
    required TextStyle style,
  }) {
    Widget figure(String text) => SizedBox(
      width: _figureWidth,
      child: Text(text, textAlign: TextAlign.right, style: style),
    );
    return Row(
      children: [
        SizedBox(
          width: _choiceWidth,
          child: Text(choice, style: style),
        ),
        const Spacer(),
        figure(lifetimeTaxes),
        figure(leftToHeirs),
        figure(earliestAge),
      ],
    );
  }
}
