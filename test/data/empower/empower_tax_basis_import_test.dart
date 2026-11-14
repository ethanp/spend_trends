import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/data/empower/empower_tax_basis_import.dart';
import 'package:spend_trends/data/empower/empower_transactions_import.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:spend_trends/domain/accounts/account_tax_treatment.dart';

void main() {
  Account investment(AccountTaxTreatment treatment) => Account(
    id: treatment.name,
    externalId: treatment.name,
    name: treatment.name,
    currency: 'USD',
    balanceCents: 0,
    status: AccountStatus.ok,
    kind: AccountKind.investment,
    chosenTaxTreatment: treatment,
  );

  EmpowerHolding holding(Map<String, dynamic> json) =>
      EmpowerHolding.fromJson({'userAccountId': 1, ...json});

  final reinvestedDividend = EmpowerTransaction.fromJson({
    'userTransactionId': 9,
    'userAccountId': 1,
    'transactionDate': '2024-01-02',
    'amount': 100,
    'isCredit': false,
    'description': 'Dividend',
    'transactionType': 'Reinvest Dividend',
  });

  test('cash counts at its value; a Roth drops reinvested dividends', () {
    final holdings = [
      holding({'ticker': 'VTSAX', 'value': 1500, 'costBasis': 1000}),
      holding({'holdingType': 'Cash', 'value': 50}),
    ];
    EmpowerAccountTaxBasis basisFor(AccountTaxTreatment treatment) =>
        EmpowerAccountTaxBasis.forMappedAccounts(
          accountByEmpowerAccountId: {1: investment(treatment)},
          holdings: holdings,
          transactions: [reinvestedDividend],
        ).single;
    expect(basisFor(AccountTaxTreatment.taxable).taxBasisCents, 105000);
    expect(basisFor(AccountTaxTreatment.roth).taxBasisCents, 95000);
  });

  test('a holding with no cost leaves the account unknown', () {
    final basis = EmpowerAccountTaxBasis.forMappedAccounts(
      accountByEmpowerAccountId: {1: investment(AccountTaxTreatment.taxable)},
      holdings: [
        holding({'ticker': 'BTC.COIN', 'value': 1000}),
      ],
      transactions: const [],
    ).single;
    expect(basis.taxBasisCents, isNull);
    expect(basis.holdingsWithoutCost.single.ticker, 'BTC.COIN');
  });
}
