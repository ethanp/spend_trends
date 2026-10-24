import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/cash_flow_breakdown.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_tax_treatment.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';

/// Where the projection starts, read from live data (dollars, today).
///
/// Housing is modeled from the current mortgage (balance and latest payment)
/// rather than last year's Housing spend, which can include a home since
/// sold. Non-housing spending, take-home, and payroll contributions are the
/// last 365 days.
class const ProjectionStartingPoint({
  required final DateTime today,
  required final Map<ProjectionTaxTreatment, double> balanceByTreatment,
  required final Map<String, ProjectionTaxTreatment> treatmentByAccountId,
  required final double homeValue,
  required final double mortgageBalance,
  required final double mortgagePaymentMonthly,
  required final double takeHomeAnnual,
  required final double nonHousingSpendingAnnual,
  required final double payrollContributionsAnnual,
}) {
  /// Loans smaller than this are stale leftovers (a paid-off loan's last
  /// balance), not a mortgage.
  static const _minimumMortgageDollars = 10000;

  factory from({
    required DateTime today,
    required List<Account> accounts,
    required List<OwnedAssetWithValuations> ownedAssets,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
    required ProjectionAssumptions assumptions,
  }) {
    final liveAccounts = [
      for (final account in accounts)
        if (account.countsTowardNetWorth) account,
    ];
    final treatmentByAccountId = {
      for (final account in liveAccounts)
        account.id:
            assumptions.taxTreatmentByAccountId[account.id] ??
            ProjectionTaxTreatment.inferredFor(account),
    };
    final balanceByTreatment = {
      for (final treatment in ProjectionTaxTreatment.values) treatment: 0.0,
    };
    for (final account in liveAccounts) {
      final treatment = treatmentByAccountId[account.id]!;
      balanceByTreatment[treatment] =
          balanceByTreatment[treatment]! + account.balanceCents / 100;
    }

    final mortgages = [
      for (final account in liveAccounts)
        if (account.kind == AccountKind.loans &&
            -account.balanceCents / 100 >= _minimumMortgageDollars)
          account,
    ];
    final mortgageIds = {for (final account in mortgages) account.id};
    final yearAgo = today.startOfDay.shiftedByDays(-364);
    final cashFlowBreakdown = CashFlowBreakdown(
      categories: categories,
      accounts: accounts,
    );
    var takeHomeCents = 0;
    var nonHousingSpendingCents = 0;
    var payrollContributionCents = 0;
    BankTransaction? latestMortgagePayment;
    for (final transaction in transactions) {
      if (mortgageIds.contains(transaction.accountId) &&
          transaction.isInflow &&
          (latestMortgagePayment == null ||
              transaction.postedAt.isAfter(latestMortgagePayment.postedAt))) {
        latestMortgagePayment = transaction;
      }
      if (transaction.postedAt.startOfDay.isBefore(yearAgo)) continue;
      final contribution = cashFlowBreakdown.contributionOf(transaction);
      takeHomeCents += contribution.takeHomeCents;
      if (!SpecialCategory.isHousingId(transaction.categoryId)) {
        nonHousingSpendingCents += contribution.spendingCents;
      }
      if (SpecialCategory.isInvestmentsId(transaction.categoryId) &&
          treatmentByAccountId[transaction.accountId] ==
              ProjectionTaxTreatment.traditional) {
        payrollContributionCents += transaction.amountCents;
      }
    }

    return ProjectionStartingPoint(
      today: today.startOfDay,
      balanceByTreatment: balanceByTreatment,
      treatmentByAccountId: treatmentByAccountId,
      homeValue: [
        for (final ownedAsset in ownedAssets)
          if (ownedAsset.asset.kind == OwnedAssetKind.home &&
              !ownedAsset.asset.isSoldAsOf(today))
            ownedAsset.currentValueCents / 100,
      ].fold(0.0, (total, value) => total + value),
      mortgageBalance: mortgages.fold(
        0.0,
        (total, account) => total - account.balanceCents / 100,
      ),
      mortgagePaymentMonthly: (latestMortgagePayment?.amountCents ?? 0) / 100,
      takeHomeAnnual: takeHomeCents / 100,
      nonHousingSpendingAnnual: nonHousingSpendingCents / 100,
      payrollContributionsAnnual: payrollContributionCents / 100,
    );
  }

  double balanceFor(ProjectionTaxTreatment treatment) =>
      balanceByTreatment[treatment] ?? 0;
}
