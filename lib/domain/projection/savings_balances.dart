/// Savings by tax type, 529 money, and home equity at one moment.
abstract class const SavingsBalances() {
  double get taxable;
  double get traditional;
  double get roth;

  /// 529 money: pays college, not counted as liquid.
  double get college;
  double get homeEquity;

  double get liquid => taxable + traditional + roth;
}
