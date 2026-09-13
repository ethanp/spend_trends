import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/features/trends/net_worth_trend.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';
import 'package:spend_trends/features/trends/trends_providers.dart';

void main() {
  test('net worth chart and Current use the same account snapshots', () async {
    final knownSince = DateTime(2021, 3, 1);
    final accounts = <String, Account>{
      'investment': Account(
        id: 'investment',
        externalId: 'investment-external',
        name: 'Investment',
        currency: 'USD',
        balanceCents: 60000000,
        balanceAsOf: knownSince,
        status: AccountStatus.ok,
        kind: AccountKind.investment,
      ),
      'mortgage': Account(
        id: 'mortgage',
        externalId: 'mortgage-external',
        name: 'Mortgage',
        currency: 'USD',
        balanceCents: -20000000,
        balanceAsOf: knownSince,
        status: AccountStatus.ok,
        kind: AccountKind.loans,
      ),
    };
    final ownedAssets = [
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
            valueCents: 30000000,
            valuedOn: knownSince,
          ),
        ],
      ),
    ];
    final providerContainer = ProviderContainer(
      overrides: [
        transactionsListProvider.overrideWith((ref) async => const []),
        categoriesListProvider.overrideWith((ref) async => const []),
        categoryGroupsProvider.overrideWith((ref) async => const []),
        accountsMapProvider.overrideWith((ref) async => accounts),
        ownedAssetsListProvider.overrideWith((ref) async => ownedAssets),
      ],
    );
    addTearDown(providerContainer.dispose);

    final chartBundle = await providerContainer.read(
      trendsChartBundleProvider.future,
    );
    final currentCents = NetWorthTrend.currentCents(
      accounts: accounts.values,
      ownedAssets: ownedAssets,
    );

    expect(chartBundle.netWorth.first.latestRollingCents, currentCents);
  });
}
