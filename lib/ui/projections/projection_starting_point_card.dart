import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/accounts/account_tax_treatment.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';

/// What the projection reads from live data: the last 365 days, the home,
/// and each tax bucket's total. The accounts behind a bucket are on Banks.
class const ProjectionStartingPointCard({
  required final RetirementProjection projection,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final start = projection.start;
    return ECard(
      kind: ESurfaceKind.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Starting point (live)', style: EText.section),
          const SizedBox(height: ELayout.spaceSm),
          ELabelValueTable(
            rows: [
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
              _figure('Home value', start.homeValue),
              ..._lifeEventsApplyingToday(),
              const SizedBox(height: ELayout.spaceMd),
              for (final treatment in AccountTaxTreatment.values)
                if (treatment != AccountTaxTreatment.excluded)
                  ..._taxBucket(treatment),
            ],
          ),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            'Each account’s balance and tax type are on Banks.',
            style: EText.caption,
          ),
        ],
      ),
    );
  }

  /// The job and home life events in effect today, which replace live
  /// take-home and set housing costs.
  List<Widget> _lifeEventsApplyingToday() {
    final Job? job = projection.lifePlan.jobOn(projection.start.today);
    final HomeOwnership? home = projection.lifePlan.homeOn(
      projection.start.today,
    );
    return [
      if (job != null)
        _figure('Take-home at ${job.title}', job.takeHomeAnnual.toDouble()),
      if (home != null)
        _figure(
          'Carrying costs / year at ${home.title}',
          home.carryingCostAnnual(projection.start.homeValue),
        ),
    ];
  }

  /// The bucket total; for Roth and taxable, how much of it has a
  /// recorded tax basis.
  List<Widget> _taxBucket(AccountTaxTreatment treatment) {
    return [
      _figure(
        treatment.label,
        projection.start.balanceFor(treatment),
        color: treatment.color,
        bold: true,
      ),
      if (treatment == AccountTaxTreatment.taxable ||
          treatment == AccountTaxTreatment.roth)
        _figure(
          '${treatment == AccountTaxTreatment.roth ? 'Contributions' : 'Cost'}'
          ' recorded · '
          '${formatCentsWholeDollars((projection.start.balanceWithoutTaxBasisFor(treatment) * 100).round())}'
          ' unknown',
          projection.start.taxBasisByTreatment[treatment] ?? 0,
          indent: true,
        ),
    ];
  }

  Widget _figure(
    String label,
    double dollars, {
    Color? color,
    bool bold = false,
    bool indent = false,
  }) {
    final weight = bold ? FontWeight.w700 : null;
    return Padding(
      padding: EdgeInsets.only(
        left: indent ? ELayout.spaceMd : 0,
        top: 2,
        bottom: 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: EText.caption.copyWith(color: color, fontWeight: weight),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: ELayout.spaceMd),
          Text(
            formatCentsWholeDollars((dollars * 100).round()),
            style: EText.caption.copyWith(
              color: EColors.textPrimary,
              fontWeight: weight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
