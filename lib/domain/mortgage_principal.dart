import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/projection/life_plan.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';

/// Mortgage principal paid from pay on [day]. It becomes home equity, so the
/// three numbers count it as Investments, not Housing in Fixed costs.
class const MortgagePrincipalPayment({
  required final CalendarDay day,
  required final int cents,

  /// Paid on the loan of a home you had already moved out of (two homes
  /// overlapping), whose payments are excluded from lifestyle costs.
  required final bool isHomeOverlap,
});

/// Every mortgage principal payment from pay through a day. The bank's
/// payment from checking has no principal/interest split, so:
///
/// - Measured where a loan account has balance snapshots: each drop in what
///   it owes, dated the later snapshot. Asset-sale credits to the loan (the
///   payoff at a home's sale) are not from pay, so they come off the drop;
///   once a loan owes nothing it is closed and later snapshots are ignored.
/// - Amortized from a home life event's loan terms before then: one payment
///   due the first of each month after the home's start, until the first
///   snapshot of a loan account opened while that home applies (the same
///   loan, as its servicer reports it).
/// - A drop on a loan opened before the home you lived in that day is a home
///   overlap.
class const MortgagePrincipal(final List<MortgagePrincipalPayment> payments) {
  factory from({
    required CalendarDay through,
    required List<Account> accounts,
    required List<AccountBalanceSnapshot> balanceSnapshots,
    required List<BankTransaction> transactions,
    required List<LifeEvent> lifeEvents,
  }) {
    final Set<String> loanAccountIds = {
      for (final account in accounts)
        if (account.kind == AccountKind.loans) account.id,
    };
    final Map<String, List<AccountBalanceSnapshot>> snapshotsByLoanId = {};
    for (final snapshot in balanceSnapshots) {
      if (!loanAccountIds.contains(snapshot.accountId)) continue;
      snapshotsByLoanId.putIfAbsent(snapshot.accountId, () => []).add(snapshot);
    }
    for (final loanSnapshots in snapshotsByLoanId.values) {
      loanSnapshots.sort(
        (left, right) => left.recordedDay.compareTo(right.recordedDay),
      );
    }
    final Map<String, List<BankTransaction>> assetSalesByLoanId = {};
    for (final transaction in transactions) {
      if (!loanAccountIds.contains(transaction.accountId) ||
          !SpecialCategory.isAssetSaleId(transaction.categoryId)) {
        continue;
      }
      assetSalesByLoanId
          .putIfAbsent(transaction.accountId, () => [])
          .add(transaction);
    }
    final lifePlan = LifePlan(lifeEvents);
    final List<CalendarDay> loanOpenedDays = [
      for (final loanSnapshots in snapshotsByLoanId.values)
        loanSnapshots.first.recordedDay,
    ];
    return MortgagePrincipal([
      for (final entry in snapshotsByLoanId.entries)
        ..._measuredPayments(
          entry.value,
          assetSales: assetSalesByLoanId[entry.key] ?? const [],
          lifePlan: lifePlan,
          through: through,
        ),
      for (final lifeEvent in lifeEvents)
        if (lifeEvent is HomeOwnership)
          ..._amortizedPayments(
            lifeEvent,
            lifePlan: lifePlan,
            loanOpenedDays: loanOpenedDays,
            through: through,
          ),
    ]);
  }

  /// Drops in what one loan owes between its snapshots (oldest first).
  static Iterable<MortgagePrincipalPayment> _measuredPayments(
    List<AccountBalanceSnapshot> loanSnapshots, {
    required List<BankTransaction> assetSales,
    required LifePlan lifePlan,
    required CalendarDay through,
  }) sync* {
    final CalendarDay loanOpenedDay = loanSnapshots.first.recordedDay;
    for (var index = 1; index < loanSnapshots.length; index++) {
      final AccountBalanceSnapshot before = loanSnapshots[index - 1];
      final AccountBalanceSnapshot after = loanSnapshots[index];
      if (before.balanceCents >= 0 || after.recordedDay.isAfter(through)) {
        return;
      }
      final int paidFromSaleCents = assetSales
          .where(
            (assetSale) =>
                assetSale.postedDay.isAfter(before.recordedDay) &&
                !assetSale.postedDay.isAfter(after.recordedDay),
          )
          .fold(0, (sum, assetSale) => sum + assetSale.amountCents);
      final int principalCents =
          after.balanceCents - before.balanceCents - paidFromSaleCents;
      if (principalCents <= 0) continue;
      final HomeOwnership? homeLivedIn = lifePlan.homeOn(
        after.recordedDay.localMidnight,
      );
      yield MortgagePrincipalPayment(
        day: after.recordedDay,
        cents: principalCents,
        isHomeOverlap:
            homeLivedIn != null &&
            loanOpenedDay.isBefore(homeLivedIn.startedOn.calendarDay),
      );
    }
  }

  /// [home]'s scheduled principal before its loan shows up in snapshots.
  static Iterable<MortgagePrincipalPayment> _amortizedPayments(
    HomeOwnership home, {
    required LifePlan lifePlan,
    required List<CalendarDay> loanOpenedDays,
    required CalendarDay through,
  }) sync* {
    final Mortgage? mortgage = home.mortgage;
    if (mortgage == null) return;
    final CalendarDay boughtDay = home.startedOn.calendarDay;
    var measuredFrom = through.plusDays(1);
    for (final loanOpenedDay in loanOpenedDays) {
      if (loanOpenedDay.isBefore(boughtDay) ||
          !home.appliesOn(loanOpenedDay.localMidnight)) {
        continue;
      }
      if (loanOpenedDay.isBefore(measuredFrom)) measuredFrom = loanOpenedDay;
    }
    var dueDay = boughtDay.startOfNextMonth;
    for (final principal in mortgage.principalPaidEachMonth(
      home.loanAmount.toDouble(),
    )) {
      if (!dueDay.isBefore(measuredFrom) ||
          !home.appliesOn(dueDay.localMidnight)) {
        return;
      }
      yield MortgagePrincipalPayment(
        day: dueDay,
        cents: (principal * 100).round(),
        isHomeOverlap: lifePlan.homeOn(dueDay.localMidnight)?.id != home.id,
      );
      dueDay = dueDay.startOfNextMonth;
    }
  }
}
