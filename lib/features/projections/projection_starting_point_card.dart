import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_tax_treatment.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_card.dart';

/// What the projection reads from live data, with each tax bucket's
/// accounts listed under it.
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
              for (final treatment in AccountTaxTreatment.values)
                if (treatment != AccountTaxTreatment.excluded)
                  ..._taxBucket(treatment, accounts),
            ],
          ),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            'Set an account’s tax type on Banks. Accounts with no balance '
            'are hidden.',
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

  /// The bucket total, then its accounts largest first.
  List<Widget> _taxBucket(
    AccountTaxTreatment treatment,
    Map<String, Account> accounts,
  ) {
    final bucketAccounts = [
      for (final entry in projection.start.treatmentByAccountId.entries)
        if (entry.value == treatment)
          if (accounts[entry.key] case final Account account)
            if (account.balanceCents != 0) account,
    ]..sort((left, right) => right.balanceCents.compareTo(left.balanceCents));
    return [
      const SizedBox(height: ELayout.spaceMd),
      _figure(
        treatment.label,
        projection.start.balanceFor(treatment),
        color: treatment.color,
        bold: true,
      ),
      for (final account in bucketAccounts)
        _figure(
          account.displayNameWithInstitution,
          account.balanceCents / 100,
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
