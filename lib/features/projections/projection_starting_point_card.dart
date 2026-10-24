import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/projection/projection_tax_treatment.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/projections/projections_providers.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_card.dart';

/// What the projection reads from live data, and each account's tax type.
class const ProjectionStartingPointCard({
  required final RetirementProjection projection,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, Account> accounts =
        ref.watch(accountsMapProvider).asData?.value ?? const {};
    final start = projection.start;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Starting point (live)', style: EText.section),
          const SizedBox(height: ELayout.spaceSm),
          _figure('Take-home, last 365 days', start.takeHomeAnnual),
          _figure(
            'Non-housing spending, last 365 days',
            start.nonHousingSpendingAnnual,
          ),
          _figure(
            '401(k) payroll contributions, last 365 days',
            start.payrollContributionsAnnual,
          ),
          _figure('Mortgage balance', start.mortgageBalance),
          _figure('Mortgage payment / month', start.mortgagePaymentMonthly),
          _figure('Home value', start.homeValue),
          const SizedBox(height: ELayout.spaceMd),
          for (final treatment in ProjectionTaxTreatment.values)
            if (treatment != ProjectionTaxTreatment.excluded)
              _figure(
                treatment.label,
                start.balanceFor(treatment),
                color: treatment.color,
              ),
          const SizedBox(height: ELayout.spaceMd),
          Text(
            'Tax type by account',
            style: EText.caption.copyWith(fontWeight: FontWeight.w700),
          ),
          for (final entry in start.treatmentByAccountId.entries)
            if (accounts[entry.key] case final Account account)
              _accountTaxTypeRow(ref, account, entry.value),
        ],
      ),
    );
  }

  Widget _figure(String label, double dollars, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: EText.caption.copyWith(color: color)),
          ),
          Text(
            formatCentsWholeDollars((dollars * 100).round()),
            style: EText.caption.copyWith(
              color: EColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountTaxTypeRow(
    WidgetRef ref,
    Account account,
    ProjectionTaxTreatment treatment,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${account.displayNameWithInstitution} · '
            '${formatCentsWholeDollars(account.balanceCents)}',
            style: EText.caption,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DropdownButton<ProjectionTaxTreatment>(
          value: treatment,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: EText.caption.copyWith(color: treatment.color),
          items: [
            for (final option in ProjectionTaxTreatment.values)
              DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: (selected) {
            if (selected == null || selected == treatment) return;
            _overrideTaxTreatment(ref, account.id, selected);
          },
        ),
      ],
    );
  }

  Future<void> _overrideTaxTreatment(
    WidgetRef ref,
    String accountId,
    ProjectionTaxTreatment treatment,
  ) async {
    final overrides = {
      for (final entry
          in projection.assumptions.taxTreatmentByAccountId.entries)
        entry.key: entry.value.name,
      accountId: treatment.name,
    };
    await ref.read(projectionAssumptionsEditorProvider).apply({
      'taxTreatmentByAccountId': overrides,
    });
  }
}
