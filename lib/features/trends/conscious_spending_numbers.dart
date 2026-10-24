import 'package:ethan_utils/ethan_utils.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/cash_flow_breakdown.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/transaction.dart';

/// Look-back windows the three numbers are shown over, longest first.
enum ConsciousSpendingWindow({
  required final int days,
  required final String label,
}) {
  twoYears(days: 730, label: '2y'),
  oneYear(days: 365, label: '1y'),
  sixMonths(days: 183, label: '6mo'),
}

/// Plain totals (no smoothing) of take-home pay and each conscious spending
/// area over [window] ending [lastDay].
class const ConsciousSpendingWindowTotals({
  required final ConsciousSpendingWindow window,
  required final DateTime firstDay,
  required final DateTime lastDay,
  required final int takeHomeCents,
  required final Map<ConsciousSpendingArea, int> centsByArea,
}) {
  int? percentOfTakeHome(ConsciousSpendingArea area) => area.percentOfIncome(
    areaCents: centsByArea[area]!,
    incomeCents: takeHomeCents,
  );

  /// Per year, so windows of different lengths compare directly.
  int annualCents(ConsciousSpendingArea area) =>
      (centsByArea[area]! * 365 / window.days).round();

  int get annualTakeHomeCents => (takeHomeCents * 365 / window.days).round();
}

/// The three numbers over each [ConsciousSpendingWindow], all ending [lastDay].
class const ConsciousSpendingNumbers({
  required final DateTime lastDay,
  required final Map<ConsciousSpendingWindow, ConsciousSpendingWindowTotals>
  totalsByWindow,
}) {
  factory endingOn({
    required DateTime today,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
    required List<Account> accounts,
  }) {
    final lastDay = today.startOfDay;
    final cashFlowBreakdown = CashFlowBreakdown(
      categories: categories,
      accounts: accounts,
    );
    return ConsciousSpendingNumbers(
      lastDay: lastDay,
      totalsByWindow: {
        for (final window in ConsciousSpendingWindow.values)
          window: _totalsOver(
            window,
            lastDay: lastDay,
            transactions: transactions,
            cashFlowBreakdown: cashFlowBreakdown,
          ),
      },
    );
  }

  static ConsciousSpendingWindowTotals _totalsOver(
    ConsciousSpendingWindow window, {
    required DateTime lastDay,
    required List<BankTransaction> transactions,
    required CashFlowBreakdown cashFlowBreakdown,
  }) {
    final firstDay = lastDay.shiftedByDays(-(window.days - 1));
    var takeHomeCents = 0;
    final centsByArea = {
      for (final area in ConsciousSpendingArea.values) area: 0,
    };
    for (final transaction in transactions) {
      final day = transaction.postedAt.startOfDay;
      if (day.isBefore(firstDay) || day.isAfter(lastDay)) continue;
      final contribution = cashFlowBreakdown.contributionOf(transaction);
      takeHomeCents += contribution.takeHomeCents;
      final area = contribution.area;
      if (area == null) continue;
      centsByArea[area] = centsByArea[area]! + contribution.areaCents;
    }
    return ConsciousSpendingWindowTotals(
      window: window,
      firstDay: firstDay,
      lastDay: lastDay,
      takeHomeCents: takeHomeCents,
      centsByArea: centsByArea,
    );
  }

  ConsciousSpendingWindowTotals totalsFor(ConsciousSpendingWindow window) =>
      totalsByWindow[window]!;

  /// e.g. `2y · 1y · 6mo ending Oct 24, 2026`
  String get periodLabel =>
      '${ConsciousSpendingWindow.values.map((window) => window.label).join(' · ')}'
      ' ending ${DateFormat.yMMMd().format(lastDay)}';
}
