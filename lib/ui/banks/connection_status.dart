import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';
import 'package:spend_trends/data/simplefin/simplefin_models.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/data/repositories/simplefin_pull_history.dart';

import 'package:spend_trends/data/simplefin/simplefin_access_store.dart';

/// SimpleFIN bank-link status (not PowerSync).
class const ConnectionStatus({
  required final bool isConnected,
  required final bool fromEnv,
  required final List<Account> accounts,
  required final List<SimpleFinError> errors,
  final DateTime? lastSyncedAt,
  final SimpleFinPullRecord? latestFinishedPull,
  final SimpleFinPullRecord? latestRunningPull,
});

final connectionStatusProvider = FutureProvider<ConnectionStatus>((ref) async {
  ref.watch(spendDataChangedProvider);
  final accessStore = ref.watch(simpleFinAccessStoreProvider);
  final accountsRepository = await ref.watch(accountsRepositoryProvider.future);
  final simpleFinPullHistory = await ref.watch(
    simpleFinPullHistoryProvider.future,
  );
  return ConnectionStatus(
    isConnected: await accessStore.isConnected,
    fromEnv: accessStore.isConfiguredInEnv,
    accounts: await accountsRepository.listAccounts(),
    errors: await simpleFinPullHistory.lastErrors(),
    lastSyncedAt: await simpleFinPullHistory.lastSuccessfulPullAt(),
    latestFinishedPull: await simpleFinPullHistory.latestFinished(),
    latestRunningPull: await simpleFinPullHistory.latestRunning(),
  );
});
