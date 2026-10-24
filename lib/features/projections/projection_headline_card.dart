import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/widgets/app_card.dart';

/// Earliest safe retirement age next to the planned one.
class const ProjectionHeadlineCard({
  required final RetirementProjection projection,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final int? currentAge = projection.currentAge;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RETIREMENT',
            style: EText.label.small.copyWith(
              color: EColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: ELayout.spaceSm),
          if (currentAge == null)
            Text(
              'Set your birth date below to run the projection.',
              style: EText.body.medium,
            )
          else ...[
            Text(_earliestRetirementCaption(), style: EText.section),
            const SizedBox(height: ELayout.spaceXs),
            Text(_plannedRetirementCaption(), style: EText.caption),
          ],
        ],
      ),
    );
  }

  String _earliestRetirementCaption() {
    final int? earliest = projection.earliestRetirementAge;
    if (earliest == null) {
      return 'Savings run out before ${projection.assumptions.endAge} '
          'at any retirement age';
    }
    final year =
        projection.start.today.year + earliest - projection.currentAge!;
    return 'Earliest retirement: age $earliest ($year)';
  }

  String _plannedRetirementCaption() {
    final assumptions = projection.assumptions;
    final atRetirement = projection.years
        .where((year) => year.age == assumptions.retirementAge)
        .firstOrNull;
    final ProjectionYear? firstShortfall = projection.years
        .where((year) => year.liquid < 0)
        .firstOrNull;
    final String endCaption = firstShortfall == null
        ? '${formatCentsWholeDollars((projection.years.last.liquid * 100).round())} '
              'liquid at ${assumptions.endAge}'
        : 'runs out at ${firstShortfall.age}';
    final String retirementCaption = atRetirement == null
        ? ''
        : ' · ${formatCentsWholeDollars((atRetirement.liquid * 100).round())} '
              'liquid then';
    return 'Planned: age ${assumptions.retirementAge}$retirementCaption · '
        '$endCaption. Today’s dollars.';
  }
}
