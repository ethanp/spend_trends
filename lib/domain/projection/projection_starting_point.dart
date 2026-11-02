import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:spend_trends/domain/categories/cash_flow_breakdown.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/accounts/owned_asset.dart';
import 'package:spend_trends/domain/accounts/owned_asset_kind.dart';
import 'package:spend_trends/domain/accounts/account_tax_treatment.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';

/// Where the projection starts, read from live data (dollars, today).
///
/// Home value and mortgage balance are today's; the home life event supplies
/// the loan's terms and carrying costs (last year's Housing spend can include
/// a home since sold). Non-housing lifestyle spending (excluded spending out),
/// take-home, and payroll contributions (401(k), HSA) are the last 365 days.
class const ProjectionStartingPoint({
  required final DateTime today,
  required final Map<AccountTaxTreatment, double> balanceByTreatment,
  required final Map<String, AccountTaxTreatment> treatmentByAccountId,
  required final double homeValue,
  required final double mortgageBalance,
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
  }) {
    final liveAccounts = [
      for (final account in accounts)
        if (account.countsTowardNetWorth) account,
    ];
    final treatmentByAccountId = {
      for (final account in liveAccounts) account.id: account.taxTreatment,
    };
    final balanceByTreatment = {
      for (final treatment in AccountTaxTreatment.values) treatment: 0.0,
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
    final CalendarDay yearAgo = today.calendarDay.plusDays(-364);
    final cashFlowBreakdown = CashFlowBreakdown(
      categories: categories,
      accounts: accounts,
    );
    var takeHomeCents = 0;
    var nonHousingSpendingCents = 0;
    var payrollContributionCents = 0;
    for (final transaction in transactions) {
      if (transaction.postedDay.isBefore(yearAgo)) continue;
      final contribution = cashFlowBreakdown.contributionOf(transaction);
      takeHomeCents += contribution.takeHomeCents;
      payrollContributionCents += contribution.payrollContributionCents;
      if (!SpecialCategory.isHousingId(transaction.categoryId)) {
        nonHousingSpendingCents += contribution.lifestyleSpendingCents;
      }
    }

    return ProjectionStartingPoint(
      today: today.startOfDay,
      balanceByTreatment: balanceByTreatment,
      treatmentByAccountId: treatmentByAccountId,
      homeValue: [
        for (final ownedAsset in ownedAssets)
          if (ownedAsset.asset.kind == OwnedAssetKind.home &&
              !ownedAsset.asset.isSoldAsOf(today.calendarDay))
            ownedAsset.currentValueCents / 100,
      ].fold(0.0, (total, value) => total + value),
      mortgageBalance: mortgages.fold(
        0.0,
        (total, account) => total - account.balanceCents / 100,
      ),
      takeHomeAnnual: takeHomeCents / 100,
      nonHousingSpendingAnnual: nonHousingSpendingCents / 100,
      payrollContributionsAnnual: payrollContributionCents / 100,
    );
  }

  double balanceFor(AccountTaxTreatment treatment) =>
      balanceByTreatment[treatment] ?? 0;
}
