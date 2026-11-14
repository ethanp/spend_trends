import 'dart:math' as math;

import 'package:spend_trends/domain/projection/life_event.dart';

/// The home held through one projection run: its value (today's dollars),
/// the loan's nominal balance and fixed payment, and moving between homes.
class ProjectedHome({
  required HomeOwnership? home,
  required double value,
  required double mortgageBalanceNominal,
}) {
  HomeOwnership? _home = home;
  double _value = value;
  double _mortgageBalanceNominal = mortgageBalanceNominal;
  double _principalAndInterestAnnualNominal =
      home?.mortgage?.principalAndInterestAnnual(home.loanAmount.toDouble()) ??
      0;

  double equity({required double priceLevel}) =>
      _value - _mortgageBalanceNominal / priceLevel;

  /// Upkeep, property tax, insurance, and HOA.
  double get carryingCostAnnual => _home?.carryingCostAnnual(_value) ?? 0;

  /// When [nextHome] is a different home: carries the one held for the new
  /// home's [HomeOwnership.monthsCarryingPreviousHome], sells it, and buys
  /// the new one. Null when the home is the same.
  HomeMove? moveTo(HomeOwnership? nextHome, {required double priceLevel}) {
    final HomeOwnership? previousHome = _home;
    if (nextHome?.id == previousHome?.id) return null;
    final double carryingUntilSold = nextHome == null || previousHome == null
        ? 0
        : nextHome.monthsCarryingPreviousHome /
              12 *
              (_principalAndInterestAnnualNominal / priceLevel +
                  previousHome.carryingCostAnnual(_value));
    final double sellingCosts =
        _value *
        (previousHome?.sellingCostPercent ??
            HomeOwnership.lastSaleSellingCostPercent) /
        100;
    final double buyingCosts = nextHome == null
        ? 0
        : nextHome.price * nextHome.closingCostPercent / 100 +
              nextHome.movingCost;
    final double costs = carryingUntilSold + sellingCosts + buyingCosts;
    final double cashFreed =
        equity(priceLevel: priceLevel) -
        costs -
        (nextHome == null ? 0 : nextHome.price - nextHome.loanAmount);
    _home = nextHome;
    _value = (nextHome?.price ?? 0).toDouble();
    _mortgageBalanceNominal = (nextHome?.loanAmount ?? 0) * priceLevel;
    _principalAndInterestAnnualNominal =
        nextHome?.mortgage?.principalAndInterestAnnual(
          _mortgageBalanceNominal,
        ) ??
        0;
    return HomeMove(costs: costs, cashFreed: cashFreed);
  }

  /// The fixed nominal principal and interest until payoff, in today's
  /// dollars; none without a home event's mortgage terms.
  MortgagePaidInAYear payTheMortgageForAYear({required double priceLevel}) {
    final Mortgage? mortgage = _home?.mortgage;
    if (mortgage == null || _mortgageBalanceNominal <= 0) {
      return const MortgagePaidInAYear(principalAndInterest: 0, principal: 0);
    }
    final interest = _mortgageBalanceNominal * mortgage.ratePercent / 100;
    final paid = math.min(
      _principalAndInterestAnnualNominal,
      _mortgageBalanceNominal + interest,
    );
    _mortgageBalanceNominal += interest - paid;
    return MortgagePaidInAYear(
      principalAndInterest: paid / priceLevel,
      principal: (paid - interest) / priceLevel,
    );
  }

  /// Tax and insurance the servicer collects while the loan is being paid.
  double escrowedTaxAndInsurance(double principalAndInterest) {
    final HomeOwnership? home = _home;
    if (home == null ||
        home.mortgage?.hasEscrow != true ||
        principalAndInterest == 0) {
      return 0;
    }
    return home.propertyTaxAnnual(_value) + home.insuranceAnnual;
  }
}

/// A move's costs (carrying the old home until it sells, selling it, buyer
/// closing costs, movers) and the cash it frees: the old home's equity
/// after those costs, less the new home's cash part. Negative when buying
/// takes more than selling frees.
class const HomeMove({
  required final double costs,
  required final double cashFreed,
});

/// One year's mortgage payments, today's dollars.
class const MortgagePaidInAYear({
  required final double principalAndInterest,

  /// The part of [principalAndInterest] that paid down the loan.
  required final double principal,
});
