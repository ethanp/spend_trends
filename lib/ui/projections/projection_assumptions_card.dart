import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/projection/assumption_sweep.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/ui/projections/projections_providers.dart';
import 'package:spend_trends/use_cases/projection/projection_assumptions_editor.dart';
import 'package:spend_trends/ui/widgets/app_date_picker.dart';

import 'assumption_slider_row.dart';

/// Projection assumptions as sliders. Dragging re-runs the projection on
/// every frame; under each slider, a line shows the result across its
/// range.
class const ProjectionAssumptionsCard({
  required final RetirementProjection projection,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ECard(
      kind: ESurfaceKind.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assumptions', style: EText.section),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            'Today’s dollars. The line under each slider is what it does '
            'across its range: % of pay to invest to retire at '
            '${projection.assumptions.retirementAge}, or for spending, the '
            'earliest retirement age. Jobs, homes, and children are life '
            'events; an assumed move tries one without adding it there.',
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
              _AssumedMoveSwitchRow(projection: projection),
              if (projection.assumptions.assumedMoveYear != null)
                for (final slider in _assumedMoveSliders())
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

  /// The assumed move's year, price, down payment, and rate. Every sweep
  /// reads the % of pay needed, so the cost of each choice shows.
  List<AssumptionSlider> _assumedMoveSliders() {
    final int thisYear = DateTime.now().year;
    return [
      AssumptionSlider(
        label: 'Move in',
        range: AssumptionSweepRange(
          assumptionKey: 'assumedMoveYear',
          min: thisYear.toDouble(),
          max: (thisYear + 25).toDouble(),
          step: 1,
          outcomeKind: SweepOutcomeKind.investingPercentNeeded,
        ),
        caption: (value) => '${value.round()}',
      ),
      AssumptionSlider(
        label: 'New home price',
        range: const AssumptionSweepRange(
          assumptionKey: 'assumedMovePrice',
          min: 250000,
          max: 2000000,
          step: 10000,
          outcomeKind: SweepOutcomeKind.investingPercentNeeded,
        ),
        caption: (value) => formatCentsWholeDollars((value * 100).round()),
      ),
      AssumptionSlider(
        label: 'Down payment',
        range: const AssumptionSweepRange(
          assumptionKey: 'assumedMoveDownPayment',
          min: 0,
          max: 1000000,
          step: 5000,
          outcomeKind: SweepOutcomeKind.investingPercentNeeded,
        ),
        caption: (value) => formatCentsWholeDollars((value * 100).round()),
      ),
      AssumptionSlider(
        label: 'Mortgage rate',
        range: const AssumptionSweepRange(
          assumptionKey: 'assumedMoveMortgageRatePercent',
          min: 3,
          max: 9,
          step: 0.05,
          outcomeKind: SweepOutcomeKind.investingPercentNeeded,
        ),
        caption: (value) => '${value.toStringAsFixed(2)}%',
      ),
    ];
  }
}

/// Switches the assumed move on (a few years out, keeping its last price,
/// down payment, and rate) or off.
class const _AssumedMoveSwitchRow({
  required final RetirementProjection projection,
}) extends ConsumerWidget {
  static const _defaultYearsAhead = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isOn = projection.assumptions.assumedMoveYear != null;
    return Row(
      children: [
        Expanded(child: Text('Assume a move', style: EText.caption)),
        Switch(
          value: isOn,
          onChanged: (assumesMove) =>
              ref.read(projectionAssumptionsEditorProvider).apply({
                'assumedMoveYear': assumesMove
                    ? DateTime.now().year + _defaultYearsAhead
                    : null,
              }),
        ),
      ],
    );
  }
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
