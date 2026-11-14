import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/data/empower/empower_transactions_import.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_tax_treatment.dart';

/// One row of Empower's `invest/getHoldings` response.
class const EmpowerHolding({
  required final int userAccountId,
  required final String ticker,
  required final int valueCents,

  /// Null when the institution reports no cost for the holding; cash is
  /// its own cost.
  required final int? costBasisCents,
}) {
  factory fromJson(Map<String, dynamic> json) => EmpowerHolding(
    userAccountId: json['userAccountId'] as int,
    ticker:
        (json['ticker'] as String?) ?? (json['description'] as String? ?? ''),
    valueCents: ((json['value'] as num? ?? 0) * 100).round(),
    costBasisCents: switch ((json['costBasis'], json['holdingType'])) {
      (final num costBasis, _) => (costBasis * 100).round(),
      (_, 'Cash') => ((json['value'] as num? ?? 0) * 100).round(),
      _ => null,
    },
  );
}

/// The tax basis one Empower account gives its app account.
///
/// A brokerage's basis is what its holdings cost. A Roth's basis is what
/// went in (contributions and conversions): its holdings' cost includes
/// reinvested dividends, which are earnings, so those come off.
class const EmpowerAccountTaxBasis({
  required final int empowerAccountId,
  required final Account account,
  required final List<EmpowerHolding> holdings,

  /// Reinvested dividends Empower recorded on the account, as positive
  /// cents; only subtracted for a Roth.
  required final int reinvestedDividendsCents,
}) {
  int get holdingsValueCents =>
      holdings.fold(0, (total, holding) => total + holding.valueCents);

  int get holdingsCostCents => holdings.fold(
    0,
    (total, holding) => total + (holding.costBasisCents ?? 0),
  );

  List<EmpowerHolding> get holdingsWithoutCost =>
      holdings.whereL((holding) => holding.costBasisCents == null);

  bool get isRoth => account.taxTreatment == AccountTaxTreatment.roth;

  /// Null when a holding has no cost: a partial sum would understate it.
  int? get taxBasisCents {
    if (holdings.isEmpty || holdingsWithoutCost.isNotEmpty) return null;
    if (!isRoth) return holdingsCostCents;
    return (holdingsCostCents - reinvestedDividendsCents).clamp(
      0,
      holdingsCostCents,
    );
  }

  /// Every mapped account's basis, reading reinvested dividends from the
  /// transactions export.
  static List<EmpowerAccountTaxBasis> forMappedAccounts({
    required Map<int, Account> accountByEmpowerAccountId,
    required List<EmpowerHolding> holdings,
    required List<EmpowerTransaction> transactions,
  }) => accountByEmpowerAccountId.entries.mapL(
    (entry) => EmpowerAccountTaxBasis(
      empowerAccountId: entry.key,
      account: entry.value,
      holdings: holdings.whereL(
        (holding) => holding.userAccountId == entry.key,
      ),
      reinvestedDividendsCents: transactions
          .where(
            (transaction) =>
                transaction.userAccountId == entry.key &&
                transaction.isReinvestedDividend,
          )
          .fold(
            0,
            (total, transaction) => total + transaction.amountCents.abs(),
          ),
    ),
  );
}
