import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/banks/banks_net_worth_pane.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';

void main() {
  testWidgets('selected bank account shows its reconstructed balance history', (
    tester,
  ) async {
    const account = Account(
      id: 'checking',
      externalId: 'checking-external',
      name: 'Everyday Checking',
      currency: 'USD',
      balanceCents: 125000,
      status: AccountStatus.ok,
    );
    final today = DateTime.now().startOfDay;
    final firstPostedOn = today.shiftedByDays(-20);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsMapProvider.overrideWith(
            (ref) async => {account.id: account},
          ),
          transactionsListProvider.overrideWith(
            (ref) async => [
              BankTransaction(
                id: 't1',
                accountId: account.id,
                externalId: 'e1',
                postedAt: firstPostedOn,
                amountCents: 4000,
                rawDescription: 'Pay',
                normalizedMerchant: 'PAY',
                pending: false,
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BanksNetWorthPane(
              accounts: [account],
              ownedAssets: <OwnedAssetWithValuations>[],
              selectedAccountId: 'checking',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Everyday Checking'), findsWidgets);
    expect(find.text('Account type'), findsOneWidget);
    expect(find.text('Prior account of'), findsOneWidget);
    expect(find.text('Balance history'), findsOneWidget);
    expect(
      find.byTooltip(
        'Daily balance reconstructed from the current balance and posted '
        'transactions. Hover the chart to inspect a date.',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        'Use when a loan or bank account moved servicers. '
        'This balance drops out of net worth; its transactions stay in '
        'the current account\'s history.',
      ),
      findsOneWidget,
    );
    expect(find.text('Need more history'), findsNothing);
    expect(find.textContaining('current snapshot'), findsNothing);
  });

  testWidgets(
    'selected account with only a live snapshot does not draw a zero line',
    (tester) async {
      const account = Account(
        id: '401k',
        externalId: '401k-external',
        name: 'Sunrun Inc. 401(k) Plan (9-01)',
        currency: 'USD',
        balanceCents: 3831619,
        status: AccountStatus.ok,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountsMapProvider.overrideWith(
              (ref) async => {account.id: account},
            ),
            transactionsListProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BanksNetWorthPane(
                accounts: [account],
                ownedAssets: <OwnedAssetWithValuations>[],
                selectedAccountId: '401k',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('\$38,316.19'), findsOneWidget);
      expect(find.text('Balance history'), findsNothing);
      expect(
        find.textContaining('Not enough posted history to reconstruct a trend'),
        findsOneWidget,
      );
    },
  );
}
