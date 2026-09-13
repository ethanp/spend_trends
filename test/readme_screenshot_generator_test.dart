import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/trends_screen.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/banks/connection_status.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/life_chains/life_chain_providers.dart';
import 'package:spend_trends/features/life_events/life_events_providers.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';

const _phoneSize = Size(390, 844);

void main() {
  setUpAll(() async {
    await ETheme.loadFontsForWidgetTests();
    dotenv.loadFromString(envString: '', isOptional: true);
  });

  testWidgets('writes trends overview for README', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(_phoneSize);

    final fixtures = _OverviewSpend();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transactionsListProvider.overrideWith(
              (ref) async => fixtures.transactions,
            ),
            categoriesListProvider.overrideWith(
              (ref) async => fixtures.categories,
            ),
            categoryGroupsProvider.overrideWith((ref) async => fixtures.groups),
            accountsMapProvider.overrideWith((ref) async => fixtures.accounts),
            ownedAssetsListProvider.overrideWith(
              (ref) async => fixtures.ownedAssets,
            ),
            lifeEventsProvider.overrideWith((ref) async => fixtures.lifeEvents),
            housingChainProvider.overrideWith(
              (ref) async => fixtures.housingChain,
            ),
            jobChainProvider.overrideWith((ref) async => StayChain(const [])),
            connectionStatusProvider.overrideWith(
              (ref) async => ConnectionStatus(
                isConnected: true,
                fromEnv: false,
                accounts: fixtures.accounts.values.toList(),
                errors: const [],
              ),
            ),
          ],
          child: MaterialApp(
            theme: ETheme.material3Dark,
            debugShowCheckedModeBanner: false,
            home: const Material(
              color: EColors.background,
              child: TrendsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../screenshots/trends.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _OverviewSpend() {
  static const _checkingId = 'checking';

  static const coffee = SpendCategory(
    id: 'cat_coffee',
    name: 'Coffee',
    sortOrder: 1,
    archived: false,
    groupId: 'grp_everyday',
  );
  static const grocery = SpendCategory(
    id: 'cat_grocery',
    name: 'Grocery',
    sortOrder: 2,
    archived: false,
    groupId: 'grp_everyday',
  );
  static final housingCategory = SpendCategory(
    id: SpecialCategory.housing.id,
    name: 'Housing',
    sortOrder: 3,
    archived: false,
  );
  static final incomeCategory = SpendCategory(
    id: SpecialCategory.income.id,
    name: 'Income',
    sortOrder: 1000,
    archived: false,
    groupId: SpecialCategory.incomeGroupId,
  );

  List<SpendCategory> get categories => [
    coffee,
    grocery,
    housingCategory,
    incomeCategory,
  ];
  final groups = [
    const CategoryGroup(id: 'grp_everyday', name: 'Everyday', sortOrder: 1),
    SpecialCategory.incomeGroup,
  ];

  final accounts = <String, Account>{
    _checkingId: Account(
      id: _checkingId,
      externalId: 'checking-external',
      name: 'Everyday Checking',
      currency: 'USD',
      balanceCents: 1842500,
      balanceAsOf: DateTime(2026, 9, 1),
      status: AccountStatus.ok,
      kind: AccountKind.checking,
    ),
    'investment': Account(
      id: 'investment',
      externalId: 'investment-external',
      name: 'Brokerage',
      currency: 'USD',
      balanceCents: 62000000,
      balanceAsOf: DateTime(2026, 9, 1),
      status: AccountStatus.ok,
      kind: AccountKind.investment,
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
          valueCents: 38500000,
          valuedOn: DateTime(2024, 6, 1),
        ),
      ],
    ),
  ];

  final lifeEvents = [
    LifeEvent(
      id: 'moved',
      title: 'Moved',
      startedOn: DateTime(2024, 6, 1),
      endedOn: DateTime(2024, 6, 1),
    ),
  ];

  final housingChain = StayChain([
    ChainStay(
      id: 'apt',
      label: 'Oak St apartment',
      startedOn: DateTime(2023, 1, 1),
    ),
    ChainStay(
      id: 'house',
      label: 'Current house',
      startedOn: DateTime(2024, 6, 1),
    ),
  ]);

  List<BankTransaction> get transactions {
    final rows = <BankTransaction>[];
    var index = 0;
    for (var year = 2023; year <= 2026; year++) {
      final lastMonth = year == 2026 ? 9 : 12;
      for (var month = 1; month <= lastMonth; month++) {
        final posted = DateTime(year, month, 8);
        final housingCents = year < 2024 || (year == 2024 && month < 6)
            ? -165000
            : -240000;
        rows.addAll([
          BankTransaction(
            id: 'pay-$index',
            accountId: _checkingId,
            externalId: 'pay-$index',
            postedAt: DateTime(year, month, 1),
            amountCents: 620000,
            rawDescription: 'Payroll',
            normalizedMerchant: 'PAYROLL',
            pending: false,
            userCategoryId: incomeCategory.id,
          ),
          BankTransaction(
            id: 'coffee-$index',
            accountId: _checkingId,
            externalId: 'coffee-$index',
            postedAt: posted,
            amountCents: -(4200 + month * 80),
            rawDescription: 'Coffee Shop',
            normalizedMerchant: 'COFFEE SHOP',
            pending: false,
            userCategoryId: coffee.id,
          ),
          BankTransaction(
            id: 'grocery-$index',
            accountId: _checkingId,
            externalId: 'grocery-$index',
            postedAt: DateTime(year, month, 14),
            amountCents: -(62000 + year * 200),
            rawDescription: 'Grocery',
            normalizedMerchant: 'GROCERY',
            pending: false,
            userCategoryId: grocery.id,
          ),
          BankTransaction(
            id: 'housing-$index',
            accountId: _checkingId,
            externalId: 'housing-$index',
            postedAt: DateTime(year, month, 3),
            amountCents: housingCents,
            rawDescription: 'Housing',
            normalizedMerchant: 'HOUSING',
            pending: false,
            userCategoryId: housingCategory.id,
          ),
        ]);
        index += 1;
      }
    }
    return rows;
  }
}
