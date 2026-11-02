import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/category_group.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/accounts/owned_asset.dart';
import 'package:spend_trends/domain/accounts/owned_asset_kind.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/data/repositories/imported_net_worth_days_repository.dart';
import 'package:spend_trends/ui/trends/trends_providers.dart';
import 'package:spend_trends/ui/trends/trends_screen.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/data/repositories/account_balance_snapshots_repository.dart';
import 'package:spend_trends/ui/banks/connection_status.dart';
import 'package:spend_trends/data/repositories/categories_repository.dart';
import 'package:spend_trends/data/repositories/life_events_repository.dart';
import 'package:spend_trends/data/repositories/owned_assets_repository.dart';

/// Tall enough for the three-numbers card and the first trend chart.
const _screenshotSize = Size(390, 1600);

void main() {
  setUpAll(() async {
    await ETheme.loadFontsForWidgetTests();
    dotenv.loadFromString(envString: '', isOptional: true);
  });

  testWidgets('writes trends overview for README', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(_screenshotSize);

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
            accountBalanceSnapshotsProvider.overrideWith(
              (ref) async => const [],
            ),
            importedNetWorthDaysProvider.overrideWith((ref) async => const []),
            ownedAssetsListProvider.overrideWith(
              (ref) async => fixtures.ownedAssets,
            ),
            lifeEventsProvider.overrideWith((ref) async => fixtures.lifeEvents),
            syncStatusDetailsProvider.overrideWithValue(
              SyncStatusDetails(
                phase: SyncPhase.synced,
                caption: 'Synced',
                connected: true,
              ),
            ),
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
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(TrendsScreen)),
      );
      // Both compute in Isolate.run, which never finishes under fake async.
      for (
        var attempt = 0;
        attempt < 100 &&
            !(container.read(trendsChartBundleProvider).hasValue &&
                container.read(consciousSpendingNumbersProvider).hasValue);
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../screenshots/trends.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }, tags: 'readme-screenshot');
}

class _OverviewSpend() {
  static const _checkingId = 'checking';

  static const coffee = SpendCategory(
    id: 'cat_coffee',
    name: 'Coffee',
    sortOrder: 1,
    archived: false,
    groupId: 'grp_everyday',
    consciousSpendingArea: ConsciousSpendingArea.guiltFree,
  );
  static const grocery = SpendCategory(
    id: 'cat_grocery',
    name: 'Grocery',
    sortOrder: 2,
    archived: false,
    groupId: 'grp_everyday',
    consciousSpendingArea: ConsciousSpendingArea.fixedCosts,
  );
  static final housingCategory = SpendCategory(
    id: SpecialCategory.housing.id,
    name: 'Housing',
    sortOrder: 3,
    archived: false,
    consciousSpendingArea: ConsciousSpendingArea.fixedCosts,
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
    SpecialCategory.investments.asSpendCategory(),
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
          valuedOn: DateTime(2024, 6, 1).calendarDay,
        ),
      ],
    ),
  ];

  final lifeEvents = [
    Milestone(
      id: 'moved',
      title: 'Moved',
      startedOn: DateTime(2024, 6, 1),
      endedOn: DateTime(2024, 6, 1),
    ),
    Rental(
      id: 'apt',
      title: 'Oak St apartment',
      startedOn: DateTime(2023, 1, 1),
      endedOn: DateTime(2024, 5, 31),
    ),
    Rental(
      id: 'house',
      title: 'Current house',
      startedOn: DateTime(2024, 6, 1),
    ),
  ];

  List<BankTransaction> get transactions {
    final rows = <BankTransaction>[];
    var index = 0;
    final now = DateTime.now();
    // Through last month, so the three-numbers windows ending today have data.
    final lastFullMonth = DateTime(now.year, now.month - 1);
    for (var year = 2023; year <= lastFullMonth.year; year++) {
      final lastMonth = year == lastFullMonth.year ? lastFullMonth.month : 12;
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
            postedAtMillis: DateTime(year, month, 1).millisecondsSinceEpoch,
            amountCents: 700000,
            rawDescription: 'Payroll',
            normalizedMerchant: 'PAYROLL',
            pending: false,
            categoryId: incomeCategory.id,
          ),
          BankTransaction(
            id: 'coffee-$index',
            accountId: _checkingId,
            externalId: 'coffee-$index',
            postedAtMillis: posted.millisecondsSinceEpoch,
            amountCents: -(4200 + month * 80),
            rawDescription: 'Coffee Shop',
            normalizedMerchant: 'COFFEE SHOP',
            pending: false,
            categoryId: coffee.id,
          ),
          BankTransaction(
            id: 'grocery-$index',
            accountId: _checkingId,
            externalId: 'grocery-$index',
            postedAtMillis: DateTime(year, month, 14).millisecondsSinceEpoch,
            amountCents: -(62000 + (year - 2023) * 2000),
            rawDescription: 'Grocery',
            normalizedMerchant: 'GROCERY',
            pending: false,
            categoryId: grocery.id,
          ),
          BankTransaction(
            id: 'housing-$index',
            accountId: _checkingId,
            externalId: 'housing-$index',
            postedAtMillis: DateTime(year, month, 3).millisecondsSinceEpoch,
            amountCents: housingCents,
            rawDescription: 'Housing',
            normalizedMerchant: 'HOUSING',
            pending: false,
            categoryId: housingCategory.id,
          ),
          BankTransaction(
            id: 'investing-$index',
            accountId: _checkingId,
            externalId: 'investing-$index',
            postedAtMillis: DateTime(year, month, 2).millisecondsSinceEpoch,
            amountCents: -60000,
            rawDescription: 'Brokerage transfer',
            normalizedMerchant: 'BROKERAGE TRANSFER',
            pending: false,
            categoryId: SpecialCategory.investments.id,
          ),
        ]);
        index += 1;
      }
    }
    return rows;
  }
}
