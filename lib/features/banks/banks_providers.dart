import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/pull_simplefin_transactions.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/simplefin/simplefin_access_store.dart';
import 'package:spend_trends/services/simplefin/simplefin_client.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/simplefin_pull_history.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

final simpleFinClientProvider = Provider<SimpleFinClient>((ref) {
  final client = SimpleFinClient();
  ref.onDispose(client.close);
  return client;
});

final simpleFinAccessStoreProvider = Provider<SimpleFinAccessStore>((ref) {
  return SimpleFinAccessStore();
});

final pullSimpleFinTransactionsProvider =
    FutureProvider<PullSimpleFinTransactions>((ref) async {
      return PullSimpleFinTransactions(
        client: ref.watch(simpleFinClientProvider),
        accessStore: ref.watch(simpleFinAccessStoreProvider),
        accountsRepository: await ref.watch(accountsRepositoryProvider.future),
        transactionsRepository: await ref.watch(
          transactionsRepositoryProvider.future,
        ),
        simpleFinPullHistory: await ref.watch(
          simpleFinPullHistoryProvider.future,
        ),
      );
    });

final simpleFinPullHistoryListProvider =
    FutureProvider<List<SimpleFinPullRecord>>((ref) async {
      ref.watch(spendDataChangedProvider);
      final history = await ref.watch(simpleFinPullHistoryProvider.future);
      return history.listRecent();
    });

final accountsMapProvider = FutureProvider<Map<String, Account>>((ref) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(accountsRepositoryProvider.future);
  final accounts = await repository.listAccounts();
  return {for (final account in accounts) account.id: account};
});
