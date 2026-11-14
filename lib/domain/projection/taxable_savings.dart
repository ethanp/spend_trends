import 'dart:math' as math;

/// Brokerage, cash, and crypto in one projection run: what it is worth and
/// what it cost, in today's dollars. Cost is fixed in nominal dollars, so
/// inflation shrinks it and creates taxable gains on its own. A negative
/// value is debt.
class TaxableSavings({required var double value, required var double cost}) {
  /// Dividends (VTI ~1.6%) are realized every year.
  static const _dividendYield = 0.016;

  /// Share of holdings sold and rebought each year, realizing its gain.
  static const _yearlyTurnoverShare = 0.10;
  static const _debtApr = 0.09;

  /// The part of a sale that is gain.
  double get _gainShare => value <= 0 ? 0 : math.max(0, 1 - cost / value);

  /// Grows a year (debt accrues instead), and reinvests dividends and the
  /// year's trades. Returns the long-term gains those realized.
  double growOneYear({required double realReturn, required double inflation}) {
    if (value < 0) {
      value += value * _debtApr;
      return 0;
    }
    value += value * realReturn;
    cost /= 1 + inflation;
    final double realizedGains =
        value * _dividendYield + value * _yearlyTurnoverShare * _gainShare;
    cost += realizedGains;
    return realizedGains;
  }

  /// Sells [amount] (at most what is held); returns the gain it realizes.
  double sell(double amount) {
    if (amount <= 0) return 0;
    final double gain = amount * _gainShare;
    cost -= amount - gain;
    value -= amount;
    return gain;
  }

  /// Adds new money: it repays any debt first, and the rest is new cost.
  void deposit(double amount) {
    final double debtRepaid = value < 0 ? math.min(amount, -value) : 0;
    value += amount;
    cost += amount - debtRepaid;
  }

  /// Spending nothing else can pay for becomes debt.
  void borrow(double amount) => value -= amount;

  TaxableSavings copy() => TaxableSavings(value: value, cost: cost);
}
