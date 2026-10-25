import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/account_tax_treatment.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/domain/projection/savings_balances.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/net_worth_trend.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

/// Actual savings on one day, in the dollars of that day unless converted.
class const SavingsOnDay({
  required final DateTime day,
  @override required final double taxable,
  @override required final double traditional,
  @override required final double roth,
  @override required final double college,
  @override required final double homeEquity,
}) extends SavingsBalances {
  /// Restated in dollars of [today], at [inflationPercent] a year.
  SavingsOnDay inDollarsOf(DateTime today, {required double inflationPercent}) {
    final yearsAgo = today.difference(day).inDays / 365.25;
    final growth = math.pow(1 + inflationPercent / 100, yearsAgo).toDouble();
    return SavingsOnDay(
      day: day,
      taxable: taxable * growth,
      traditional: traditional * growth,
      roth: roth * growth,
      college: college * growth,
      homeEquity: homeEquity * growth,
    );
  }
}

/// Real savings by tax type on the first of each month since Trends history
/// begins, plus today, from the same smoothed balances as the Trends net
/// worth line. Home equity is home valuations less loan balances.
class SavingsHistory(final List<SavingsOnDay> days) {
  factory reconstruct({
    required DateTime today,
    required List<Account> accounts,
    required List<BankTransaction> transactions,
    required List<AccountBalanceSnapshot> balanceSnapshots,
    required List<OwnedAssetWithValuations> ownedAssets,
  }) {
    final chartDates = [
      for (
        var day = TrendChartCatalog.chartHistoryStart.startOfDay;
        !day.isAfter(today.startOfDay);
        day = day.shiftedByDays(1)
      )
        day,
    ];
    final Map<Account, List<double>> balanceCentsByAccount =
        NetWorthTrend.smoothedBalanceCentsByAccount(
          accounts: accounts,
          transactions: transactions,
          balanceSnapshots: balanceSnapshots,
          chartDates: chartDates,
        );
    final List<List<double>> homeValueCentsByHome = [
      for (final ownedAsset in ownedAssets)
        if (ownedAsset.asset.kind == OwnedAssetKind.home)
          NetWorthTrend.smoothedValueCents(
            ownedAsset: ownedAsset,
            chartDates: chartDates,
          ),
    ];
    return SavingsHistory([
      for (var dayIndex = 0; dayIndex < chartDates.length; dayIndex++)
        if (chartDates[dayIndex].day == 1 || dayIndex == chartDates.length - 1)
          _savingsOn(
            chartDates[dayIndex],
            dayIndex: dayIndex,
            balanceCentsByAccount: balanceCentsByAccount,
            homeValueCentsByHome: homeValueCentsByHome,
          ),
    ]);
  }

  static SavingsOnDay _savingsOn(
    DateTime day, {
    required int dayIndex,
    required Map<Account, List<double>> balanceCentsByAccount,
    required List<List<double>> homeValueCentsByHome,
  }) {
    final centsByTreatment = {
      for (final treatment in AccountTaxTreatment.values) treatment: 0.0,
    };
    var homeEquityCents = 0.0;
    for (final MapEntry(key: account, value: dailyCents)
        in balanceCentsByAccount.entries) {
      if (account.kind == AccountKind.loans) {
        homeEquityCents += dailyCents[dayIndex];
        continue;
      }
      centsByTreatment[account.taxTreatment] =
          centsByTreatment[account.taxTreatment]! + dailyCents[dayIndex];
    }
    for (final homeValueCents in homeValueCentsByHome) {
      homeEquityCents += homeValueCents[dayIndex];
    }
    return SavingsOnDay(
      day: day,
      taxable: centsByTreatment[AccountTaxTreatment.taxable]! / 100,
      traditional: centsByTreatment[AccountTaxTreatment.traditional]! / 100,
      roth: centsByTreatment[AccountTaxTreatment.roth]! / 100,
      college: centsByTreatment[AccountTaxTreatment.college]! / 100,
      homeEquity: homeEquityCents / 100,
    );
  }

  List<SavingsOnDay> inDollarsOf(
    DateTime today, {
    required double inflationPercent,
  }) => days.mapL(
    (savingsOnDay) =>
        savingsOnDay.inDollarsOf(today, inflationPercent: inflationPercent),
  );
}
