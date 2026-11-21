import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/projection/assumption_sweep.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/domain/taxes/filing_status.dart';
import 'package:spend_trends/ui/projections/projections_providers.dart';
import 'package:spend_trends/use_cases/projection/projection_assumptions_editor.dart';
import 'package:spend_trends/ui/widgets/app_date_picker.dart';

import 'assumption_slider.dart';

/// Projection assumptions as sliders and switches, in groups. Dragging
/// re-runs the projection on every frame; under each slider, a line shows
/// the result across its range.
class const ProjectionAssumptionsCard({
  required final RetirementProjection projection,
}) extends ConsumerWidget {
  static const _assumedMoveYearsAhead = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, AssumptionSlider> sliderByKey = {
      for (final slider in _sliders()) slider.range.assumptionKey: slider,
    };
    ELabeledControlRow sliderRow(String assumptionKey) =>
        sliderByKey[assumptionKey]!.rowFor(projection);
    return ECard(
      kind: ESurfaceKind.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: ELayout.spaceMd,
        children: [
          ECardHeader(
            title: 'Assumptions',
            blurb:
                'Today’s dollars. The line under each slider is what it does '
                'across its range: % of pay to invest to retire at '
                '${projection.assumptions.retirementAge}, or for spending, '
                'the earliest retirement age. Jobs, homes, and children are '
                'life events; an assumed move tries one without adding it '
                'there. Taxes are 2026 federal brackets. Accounts with a '
                'recorded tax basis use it; the rest take the share set '
                'here. Retired before 65, the household buys the benchmark '
                'marketplace plan (priced by age) and gets the premium tax '
                'credit up to 400% of the poverty line.',
          ),
          ELabeledControlTable(
            sections: [
              ELabeledControlSection(
                title: 'You',
                rows: [
                  _birthDateRow(context, ref),
                  _filingJointlyRow(ref),
                  sliderRow('retirementAge'),
                  sliderRow('endAge'),
                ],
              ),
              ELabeledControlSection(
                title: 'Money',
                rows: [
                  sliderRow('spendingOverrideAnnualDollars'),
                  sliderRow('socialSecurityMonthlyDollars'),
                  sliderRow('marketplacePremiumMonthlyDollars'),
                ],
              ),
              ELabeledControlSection(
                title: 'Markets',
                rows: [
                  sliderRow('realReturnPercent'),
                  sliderRow('inflationPercent'),
                ],
              ),
              ELabeledControlSection(
                title: 'Tax basis',
                rows: [
                  sliderRow('taxableCostPercent'),
                  sliderRow('rothContributionsPercent'),
                ],
              ),
              ELabeledControlSection(
                title: 'Move',
                rows: [
                  _assumedMoveRow(ref),
                  if (projection.assumptions.assumedMoveYear != null)
                    for (final slider in _assumedMoveSliders())
                      slider.rowFor(projection),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens a calendar (starting on the year grid); saves the pick.
  ELabeledControlRow _birthDateRow(BuildContext context, WidgetRef ref) {
    final DateTime? birthDate = projection.assumptions.birthDate;
    return ELabeledControlRow.trailing(
      label: 'Birth date',
      child: TextButton.icon(
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

  /// Files single, or jointly with the jointly brackets and deduction.
  ELabeledControlRow _filingJointlyRow(WidgetRef ref) {
    return ELabeledControlRow.toggle(
      label: FilingStatus.marriedFilingJointly.label,
      value:
          projection.assumptions.filingStatus ==
          FilingStatus.marriedFilingJointly,
      onChanged: (filesJointly) =>
          ref.read(projectionAssumptionsEditorProvider).apply({
            'filingStatus':
                (filesJointly
                        ? FilingStatus.marriedFilingJointly
                        : FilingStatus.single)
                    .name,
          }),
    );
  }

  /// Switches the assumed move on (a few years out, keeping its last price,
  /// down payment, and rate) or off.
  ELabeledControlRow _assumedMoveRow(WidgetRef ref) {
    return ELabeledControlRow.toggle(
      label: 'Assume a move',
      value: projection.assumptions.assumedMoveYear != null,
      onChanged: (assumesMove) =>
          ref.read(projectionAssumptionsEditorProvider).apply({
            'assumedMoveYear': assumesMove
                ? DateTime.now().year + _assumedMoveYearsAhead
                : null,
          }),
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
      label: 'Taxable cost, where unknown',
      range: const AssumptionSweepRange(
        assumptionKey: 'taxableCostPercent',
        min: 0,
        max: 100,
        step: 1,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) => '${value.round()}% of value',
    ),
    AssumptionSlider(
      label: 'Roth contributions, where unknown',
      range: const AssumptionSweepRange(
        assumptionKey: 'rothContributionsPercent',
        min: 0,
        max: 100,
        step: 1,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) => '${value.round()}% of balance',
    ),
    AssumptionSlider(
      label: 'Marketplace plan, one adult today',
      range: const AssumptionSweepRange(
        assumptionKey: 'marketplacePremiumMonthlyDollars',
        min: 200,
        max: 1500,
        step: 10,
        outcomeKind: SweepOutcomeKind.investingPercentNeeded,
      ),
      caption: (value) =>
          '${formatCentsWholeDollars((value * 100).round())}/mo',
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
