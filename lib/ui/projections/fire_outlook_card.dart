import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';

import 'projections_providers.dart';

/// Top-bar card with the age and year the projection says you can FIRE,
/// following assumptions as they are dragged or saved.
class const FireOutlookCard() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RetirementProjection? projection = ref
        .watch(draftedRetirementProjectionProvider)
        .value;
    if (projection == null) return const SizedBox.shrink();
    final int? earliest = projection.earliestRetirementAge;
    if (projection.currentAge == null) {
      return _outlookPlate(
        labelColor: EColors.textMuted,
        outlook: Text('Set birth date', style: _outlookNoteStyle),
      );
    }
    if (earliest == null) {
      return _outlookPlate(
        labelColor: EColors.warning,
        outlook: Text(
          'Not before ${projection.assumptions.endAge}',
          style: _outlookNoteStyle,
        ),
      );
    }
    return _outlookPlate(
      labelColor: EColors.textMuted,
      outlook: _ageAndYear(earliest, projection.earliestRetirementYear!),
    );
  }

  Widget _outlookPlate({required Color labelColor, required Widget outlook}) {
    return ESurface(
      kind: ESurfaceKind.tinted,
      accent: EColors.textMuted,
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceMd,
        ELayout.spaceXs + 2,
        ELayout.spaceMd,
        ELayout.spaceXs + 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FIRE AT THIS RATE',
            style: EText.label.small.copyWith(
              color: labelColor,
              fontSize: ELayout.typeSize(9.5),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          outlook,
        ],
      ),
    );
  }

  Widget _ageAndYear(int age, int year) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$age',
            style: EText.section.copyWith(
              fontSize: ELayout.typeSize(20),
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: 'yo',
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
          TextSpan(
            text: '  in $year',
            style: EText.body.small.copyWith(
              color: EColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _outlookNoteStyle => EText.body.small.copyWith(
    color: EColors.textSecondary,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
}
