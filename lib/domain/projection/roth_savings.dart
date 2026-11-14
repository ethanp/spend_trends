import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';

import 'package:spend_trends/domain/taxes/retirement_account_rules.dart';

/// Roth money in one projection run, with the history the IRS orders its
/// withdrawals by: contributions first (always free), then conversions
/// oldest first (free once seasoned five tax years), then earnings (free
/// from 59½). Contributions and conversions are nominal amounts, so they
/// shrink in today's dollars. Assumes the first Roth contribution is more
/// than five years old.
class RothSavings({
  required var double balance,
  required var double contributions,
  List<RothConversion> conversions = const [],
}) {
  final List<RothConversion> _conversions = conversions.mapL(
    (conversion) => conversion.copy(),
  );

  void growOneYear({required double realReturn, required double inflation}) {
    balance += balance * realReturn;
    contributions /= 1 + inflation;
    for (final conversion in _conversions) {
      conversion.amount /= 1 + inflation;
    }
  }

  void convertIn(double amount, {required int taxYear}) {
    if (amount <= 0) return;
    balance += amount;
    _conversions.add(RothConversion(taxYear: taxYear, amount: amount));
  }

  /// What can come out in [taxYear] with no tax or penalty.
  double withdrawableFreely({
    required int taxYear,
    required bool isPastPenaltyFreeAge,
  }) {
    if (isPastPenaltyFreeAge) return balance;
    final double seasonedConversions = _conversions
        .where((conversion) => conversion.isSeasonedIn(taxYear))
        .fold(0.0, (total, conversion) => total + conversion.amount);
    return math.min(balance, contributions + seasonedConversions);
  }

  /// Takes [amount] out in withdrawal order; says what of it the penalty
  /// and income tax reach.
  RothWithdrawal withdraw(
    double amount, {
    required int taxYear,
    required bool isPastPenaltyFreeAge,
  }) {
    balance -= amount;
    final double fromContributions = math.min(amount, contributions);
    contributions -= fromContributions;
    var stillToTake = amount - fromContributions;
    var unseasonedConversionsTaken = 0.0;
    for (final conversion in _conversions) {
      if (stillToTake <= 0) break;
      final double taken = math.min(stillToTake, conversion.amount);
      conversion.amount -= taken;
      stillToTake -= taken;
      if (!conversion.isSeasonedIn(taxYear)) {
        unseasonedConversionsTaken += taken;
      }
    }
    _conversions.removeWhere((conversion) => conversion.amount <= 0);
    if (isPastPenaltyFreeAge) return const RothWithdrawal();
    return RothWithdrawal(
      unseasonedConversions: unseasonedConversionsTaken,
      earnings: stillToTake,
    );
  }

  RothSavings copy() => RothSavings(
    balance: balance,
    contributions: contributions,
    conversions: _conversions,
  );
}

/// One year's conversion still in the Roth, today's dollars.
class RothConversion({required final int taxYear, required var double amount}) {
  bool isSeasonedIn(int year) =>
      year >= taxYear + RetirementAccountRules.rothConversionSeasoningYears;

  RothConversion copy() => RothConversion(taxYear: taxYear, amount: amount);
}

/// The parts of a Roth withdrawal before 59½ that are not free: unseasoned
/// conversions pay the penalty; earnings pay income tax and the penalty.
class const RothWithdrawal({
  final double unseasonedConversions = 0,
  final double earnings = 0,
});
