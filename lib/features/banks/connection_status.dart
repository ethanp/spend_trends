import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/simplefin/simplefin_models.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/simplefin_pull_history.dart';

import 'banks_providers.dart';

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
