import 'package:spend_trends/domain/accounts/account_tax_treatment.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_starting_point.dart';
import 'package:spend_trends/domain/projection/roth_savings.dart';
import 'package:spend_trends/domain/projection/taxable_savings.dart';

/// Savings by tax type through one projection run, today's dollars. Each
/// account knows what it holds and what a move out of it means for tax;
/// when and how much to move is the [YearDrawdown]'s call.
class ProjectedSavings({
  required final TaxableSavings taxable,
  required var double traditional,
  required final RothSavings roth,

  /// 529 money: pays college years and never funds retirement.
  required var double college,
}) {
  /// Today's balances and their recorded tax basis; accounts with none
  /// take the assumed share.
  factory startingFrom(
    ProjectionStartingPoint start,
    ProjectionAssumptions assumptions,
  ) {
    final double taxableValue = start.balanceFor(AccountTaxTreatment.taxable);
    final double rothBalance = start.balanceFor(AccountTaxTreatment.roth);
    return ProjectedSavings(
      taxable: TaxableSavings(
        value: taxableValue,
        cost: start.taxBasisFor(
          AccountTaxTreatment.taxable,
          assumedBasisPercent: assumptions.taxableCostPercent,
        ),
      ),
      traditional: start.balanceFor(AccountTaxTreatment.traditional),
      roth: RothSavings(
        balance: rothBalance,
        contributions: start.taxBasisFor(
          AccountTaxTreatment.roth,
          assumedBasisPercent: assumptions.rothContributionsPercent,
        ),
      ),
      college: start.balanceFor(AccountTaxTreatment.college),
    );
  }

  double get liquid => taxable.value + traditional + roth.balance;

  /// Grows every account a year; returns the gains taxable realized.
  double growOneYear({required double realReturn, required double inflation}) {
    traditional += traditional * realReturn;
    college += college * realReturn;
    roth.growOneYear(realReturn: realReturn, inflation: inflation);
    return taxable.growOneYear(realReturn: realReturn, inflation: inflation);
  }

  ProjectedSavings copy() => ProjectedSavings(
    taxable: taxable.copy(),
    traditional: traditional,
    roth: roth.copy(),
    college: college,
  );
}
