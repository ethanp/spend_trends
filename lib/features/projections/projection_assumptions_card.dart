import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/projection/assumption_sweep.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/features/projections/projections_providers.dart';
import 'package:spend_trends/widgets/app_card.dart';
import 'package:spend_trends/widgets/app_date_picker.dart';

import 'assumption_slider_row.dart';

/// Projection assumptions as sliders. Dragging re-runs the projection on
/// every frame; under each slider, a line shows the result across its
/// range.
class const ProjectionAssumptionsCard({
  required final RetirementProjection projection,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assumptions', style: EText.section),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            'Today’s dollars. The line under each slider is what it does '
            'across its range: % of take-home to invest to retire at '
            '${projection.assumptions.retirementAge}, or for spending, the '
            'earliest retirement age. Jobs, homes, and children are life '
            'events.',
            style: EText.caption,
          ),
          const SizedBox(height: ELayout.spaceSm),
          ELabelValueTable(
            maxWidth: 720,
            rows: [
              _BirthDateRow(projection: projection),
              for (final slider in _sliders())
                AssumptionSliderRow(
                  key: ValueKey(slider.range.assumptionKey),
                  slider: slider,
                  projection: projection,
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<AssumptionSlider> _sliders() => [
    AssumptionSlider(
      label: 'Planned retirement age',
      range: const AssumptionSweepRange(
        assumptionKey: 'retirementAge',
        min: 35,
        max: 70,
        step: 1,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) => '${value.round()}',
    ),
    AssumptionSlider(
      label: 'Non-housing spending',
      range: const AssumptionSweepRange(
        assumptionKey: 'spendingOverrideAnnualDollars',
        min: 30000,
        max: 150000,
        step: 1000,
        outcomeKind: SweepOutcomeKind.earliestRetirementAge,
      ),
      actualValue: projection.start.nonHousingSpendingAnnual,
      caption: (value) =>
          '${formatCentsWholeDollars((value * 100).round())}/yr',
    ),
    AssumptionSlider(
      label: 'Real return',
      range: const AssumptionSweepRange(
        assumptionKey: 'realReturnPercent',
        min: 2,
        max: 9,
        step: 0.1,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) => '${value.toStringAsFixed(1)}%',
    ),
    AssumptionSlider(
      label: 'Inflation',
      range: const AssumptionSweepRange(
        assumptionKey: 'inflationPercent',
        min: 1,
        max: 6,
        step: 0.1,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) => '${value.toStringAsFixed(1)}%',
    ),
    AssumptionSlider(
      label: 'Retirement tax',
      range: const AssumptionSweepRange(
        assumptionKey: 'retirementTaxPercent',
        min: 0,
        max: 40,
        step: 1,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) => '${value.round()}%',
    ),
    AssumptionSlider(
      label: 'Social Security from 62',
      range: const AssumptionSweepRange(
        assumptionKey: 'socialSecurityMonthlyDollars',
        min: 0,
        max: 5000,
        step: 50,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) =>
          '${formatCentsWholeDollars((value * 100).round())}/mo',
    ),
    AssumptionSlider(
      label: 'Plan through age',
      range: const AssumptionSweepRange(
        assumptionKey: 'endAge',
        min: 80,
        max: 105,
        step: 1,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) => '${value.round()}',
    ),
  ];
}

/// Opens a calendar (starting on the year grid); saves the pick.
class const _BirthDateRow({required final RetirementProjection projection})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime? birthDate = projection.assumptions.birthDate;
    return Row(
      children: [
        Expanded(child: Text('Birth date', style: EText.caption)),
        TextButton.icon(
          onPressed: () => _pickBirthDate(context, ref, birthDate),
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text(
            birthDate == null ? 'Set' : DateFormat.yMMMd().format(birthDate),
            style: EText.caption.copyWith(color: EColors.textPrimary),
          ),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceSm),
          ),
        ),
      ],
    );
  }

  Future<void> _pickBirthDate(
    BuildContext context,
    WidgetRef ref,
    DateTime? birthDate,
  ) async {
    final ProjectionAssumptionsEditor editor = ref.read(
      projectionAssumptionsEditorProvider,
    );
    final DateTime? picked = await pickAppDate(
      context,
      initialDate: birthDate ?? DateTime(DateTime.now().year - 35),
      minimumDate: DateTime(1920),
      maximumDate: DateTime.now(),
      initialMode: DatePickerMode.year,
    );
    if (picked == null || picked == birthDate) return;
    await editor.apply({'birthDate': picked.dayKey});
  }
}
