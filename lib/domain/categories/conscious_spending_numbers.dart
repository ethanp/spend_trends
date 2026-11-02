import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_balance_snapshot.dart';
import 'package:spend_trends/domain/categories/cash_flow_breakdown.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/accounts/mortgage_principal.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';

/// Look-back windows the three numbers are shown over, longest first.
enum ConsciousSpendingWindow({
  required final int days,
  required final String label,
}) {
  twoYears(days: 730, label: '2y'),
  oneYear(days: 365, label: '1y'),
  sixMonths(days: 183, label: '6mo'),
}

/// Plain totals (no smoothing) of take-home pay, payroll contributions, and
/// each conscious spending area over [window] ending [lastDay]. Mortgage
/// principal counts as Investments: it builds home equity.
class const ConsciousSpendingWindowTotals({
  required final ConsciousSpendingWindow window,
  required final DateTime firstDay,
  required final DateTime lastDay,
  required final int takeHomeCents,
  required final int payrollContributionCents,
  required final Map<ConsciousSpendingArea, int> centsByArea,

  /// Spending its rule excludes from lifestyle costs; it fills no area.
  required final int excludedFromLifestyleCents,

  /// The part of Investments that is mortgage principal, moved there from
  /// Fixed costs (or from excluded spending during a home overlap).
  required final int mortgagePrincipalCents,
}) {
  /// Take-home plus payroll contributions: the paycheck before 401(k) and
  /// HSA came out of it. Every area is a share of this, so Investments is
  /// not pre-tax money over post-tax pay.
  int get payCents => takeHomeCents + payrollContributionCents;

  /// Pay left after the three areas and excluded spending: cash that piled
  /// up (positive) or was drawn down (negative) over the window.
  int get savingsCents =>
      payCents -
      excludedFromLifestyleCents -
      centsByArea.values.fold(0, (sum, cents) => sum + cents);

  int? percentOfPay(ConsciousSpendingArea area) =>
      _percentOfPay(centsByArea[area]!);

  int? get savingsPercentOfPay => _percentOfPay(savingsCents);

  int? get excludedFromLifestylePercentOfPay =>
      _percentOfPay(excludedFromLifestyleCents);

  /// Rounded share of pay, or null when there is no pay.
  int? _percentOfPay(int cents) {
    if (payCents <= 0) return null;
    return (cents / payCents * 100).round();
  }

  /// Per year, so windows of different lengths compare directly.
  int annualCents(ConsciousSpendingArea area) =>
      _annualized(centsByArea[area]!);

  int get annualSavingsCents => _annualized(savingsCents);

  int get annualExcludedFromLifestyleCents =>
      _annualized(excludedFromLifestyleCents);

  int get annualPayCents => _annualized(payCents);

  int get annualMortgagePrincipalCents => _annualized(mortgagePrincipalCents);

  int _annualized(int cents) => (cents * 365 / window.days).round();
}

/// The three numbers over each [ConsciousSpendingWindow], all ending [lastDay].
class const ConsciousSpendingNumbers({
  required final DateTime lastDay,
  required final Map<ConsciousSpendingWindow, ConsciousSpendingWindowTotals>
  totalsByWindow,
}) {
  /// One pass over [transactions]: each contribution is classified once and
  /// added to every window that covers its day. Mortgage principal paid in a
  /// window then moves to Investments.
  factory endingOn({
    required DateTime today,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
    required List<Account> accounts,
    required List<AccountBalanceSnapshot> balanceSnapshots,
    required List<LifeEvent> lifeEvents,
  }) {
    final CalendarDay lastDay = today.calendarDay;
    final cashFlowBreakdown = CashFlowBreakdown(
      categories: categories,
      accounts: accounts,
    );
    final List<_ConsciousSpendingWindowTally> windowTallies =
        ConsciousSpendingWindow.values.mapL(
          (window) => _ConsciousSpendingWindowTally(
            window: window,
            firstDay: lastDay.plusDays(-(window.days - 1)),
          ),
        );

    for (final transaction in transactions) {
      final CalendarDay day = transaction.postedDay;
      if (day.isAfter(lastDay) ||
          !windowTallies.any((windowTally) => windowTally.covers(day))) {
        continue;
      }
      final contribution = cashFlowBreakdown.contributionOf(transaction);
      for (final windowTally in windowTallies) {
        if (windowTally.covers(day)) windowTally.add(contribution);
      }
    }
    final mortgagePrincipal = MortgagePrincipal.from(
      through: lastDay,
      accounts: accounts,
      balanceSnapshots: balanceSnapshots,
      transactions: transactions,
      lifeEvents: lifeEvents,
    );
    for (final payment in mortgagePrincipal.payments) {
      for (final windowTally in windowTallies) {
        if (windowTally.covers(payment.day)) {
          windowTally.addMortgagePrincipal(payment);
        }
      }
    }

    return ConsciousSpendingNumbers(
      lastDay: lastDay.localMidnight,
      totalsByWindow: {
        for (final windowTally in windowTallies)
          windowTally.window: windowTally.totalsThrough(lastDay),
      },
    );
  }

  ConsciousSpendingWindowTotals totalsFor(ConsciousSpendingWindow window) =>
      totalsByWindow[window]!;
}

/// Running totals for one window while transactions and mortgage principal
/// are read.
class _ConsciousSpendingWindowTally({
  required final ConsciousSpendingWindow window,
  required final CalendarDay firstDay,
}) {
  int takeHomeCents = 0;
  int payrollContributionCents = 0;
  int excludedFromLifestyleCents = 0;
  int mortgagePrincipalCents = 0;
  final Map<ConsciousSpendingArea, int> centsByArea = {
    for (final area in ConsciousSpendingArea.values) area: 0,
  };

  /// Callers have already dropped days after the window's last day.
  bool covers(CalendarDay day) => !day.isBefore(firstDay);

  void add(CashFlowContribution contribution) {
    takeHomeCents += contribution.takeHomeCents;
    payrollContributionCents += contribution.payrollContributionCents;
    excludedFromLifestyleCents += contribution.excludedFromLifestyleCents;
    final ConsciousSpendingArea? area = contribution.area;
    if (area == null) return;
    centsByArea[area] = centsByArea[area]! + contribution.areaCents;
  }

  /// Principal leaves what its payment filled (Housing in Fixed costs, or
  /// excluded spending during a home overlap) for Investments, so Savings
  /// does not change.
  void addMortgagePrincipal(MortgagePrincipalPayment payment) {
    mortgagePrincipalCents += payment.cents;
    centsByArea[ConsciousSpendingArea.investments] =
        centsByArea[ConsciousSpendingArea.investments]! + payment.cents;
    if (payment.isHomeOverlap) {
      excludedFromLifestyleCents -= payment.cents;
      return;
    }
    centsByArea[ConsciousSpendingArea.fixedCosts] =
        centsByArea[ConsciousSpendingArea.fixedCosts]! - payment.cents;
  }

  ConsciousSpendingWindowTotals totalsThrough(CalendarDay lastDay) =>
      ConsciousSpendingWindowTotals(
        window: window,
        firstDay: firstDay.localMidnight,
        lastDay: lastDay.localMidnight,
        takeHomeCents: takeHomeCents,
        payrollContributionCents: payrollContributionCents,
        centsByArea: centsByArea,
        excludedFromLifestyleCents: excludedFromLifestyleCents,
        mortgagePrincipalCents: mortgagePrincipalCents,
      );
}
