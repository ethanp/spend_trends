import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/features/projections/savings_history.dart';

void main() {
  Account manualAccount(String id, String name, AccountKind kind, int cents) =>
      Account(
        id: id,
        externalId: 'manual:$id',
        name: name,
        currency: 'USD',
        balanceCents: cents,
        status: AccountStatus.ok,
        kind: kind,
      );

  AccountBalanceSnapshot snapshot(String accountId, DateTime day, int cents) =>
      AccountBalanceSnapshot(
        id: '$accountId@$day',
        accountId: accountId,
        balanceCents: cents,
        recordedOn: day,
      );

  final history = SavingsHistory.reconstruct(
    today: DateTime(2021, 6, 15),
    accounts: [
      manualAccount('roth', 'Roth IRA', AccountKind.investment, 1000000),
      manualAccount('mortgage', 'Mortgage', AccountKind.loans, -20000000),
    ],
    transactions: const [],
    balanceSnapshots: [
      snapshot('roth', DateTime(2021, 3, 1), 1000000),
      snapshot('mortgage', DateTime(2021, 3, 1), -20000000),
    ],
    ownedAssets: [
      OwnedAssetWithValuations(
        asset: const OwnedAsset(
          id: 'home',
          name: 'Home',
          kind: OwnedAssetKind.home,
        ),
        valuations: [
          OwnedAssetValuation(
            id: 'home-value',
            ownedAssetId: 'home',
            valueCents: 50000000,
            valuedOn: DateTime(2021, 3, 1),
          ),
        ],
      ),
    ],
  );

  test('samples the first of each month since Trends history, then today', () {
    expect(history.days.map((savingsOnDay) => savingsOnDay.day), [
      DateTime(2021, 3, 1),
      DateTime(2021, 4, 1),
      DateTime(2021, 5, 1),
      DateTime(2021, 6, 1),
      DateTime(2021, 6, 15),
    ]);
  });

  test('accounts land in their tax bucket; loans offset home value', () {
    expect(history.days[2].roth, closeTo(10000, 1));
    expect(history.days[2].liquid, closeTo(10000, 1));
    expect(history.days[2].homeEquity, closeTo(500000 - 200000, 1));
  });

  test('restating in today’s dollars grows older values by inflation', () {
    final restated = history.inDollarsOf(
      DateTime(2022, 3, 1),
      inflationPercent: 10,
    );
    expect(restated.first.roth, closeTo(11000, 5));
  });
}
