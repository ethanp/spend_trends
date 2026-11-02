import 'package:spend_trends/use_cases/categories/categorizer.dart';
import 'package:spend_trends/data/simplefin/simplefin_access_store.dart';
import 'package:spend_trends/data/simplefin/simplefin_bank_target.dart';
import 'package:spend_trends/use_cases/simplefin_pull/simplefin_account_mapper.dart';
import 'package:spend_trends/data/simplefin/simplefin_client.dart';
import 'package:spend_trends/data/simplefin/simplefin_models.dart';
import 'package:spend_trends/use_cases/simplefin_pull/simplefin_pull_outcome_accumulator.dart';
import 'package:spend_trends/use_cases/simplefin_pull/simplefin_pull_progress.dart';
import 'package:spend_trends/use_cases/simplefin_pull/simplefin_pull_windows.dart';
import 'package:spend_trends/use_cases/simplefin_pull/simplefin_transaction_mapper.dart';
import 'package:spend_trends/use_cases/simplefin_pull/simplefin_window_ingester.dart';
import 'package:spend_trends/data/repositories/account_balance_snapshots_repository.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/data/repositories/simplefin_pull_history.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logger = ELogger('PullSimpleFinTransactions');

/// Orchestrates SimpleFIN connect / pull / disconnect.
///
/// Window policy, remote→local mapping, outage journaling, and UI progress
/// DTOs live in dedicated modules under `services/simplefin/`.
class PullSimpleFinTransactions({
  required final SimpleFinClient _client,
  required final SimpleFinAccessStore _accessStore,
  required final AccountsRepository _accountsRepository,
  required AccountBalanceSnapshotsRepository snapshotsRepository,
  required TransactionsRepository transactionsRepository,
  required final SimpleFinPullHistory _simpleFinPullHistory,

  /// Runs the rules over what each pull wrote, even when it fails partway.
  required final Categorizer _categorizer,
}) {
  final SimpleFinWindowIngester _ingester = SimpleFinWindowIngester(
    client: _client,
    accountMapper: SimpleFinAccountMapper(
      accountsRepository: _accountsRepository,
      snapshotsRepository: snapshotsRepository,
    ),
    transactionMapper: SimpleFinTransactionMapper(
      transactionsRepository: transactionsRepository,
    ),
  );

  Future<SimpleFinPullResult> connectWithSetupToken(
    String setupToken, {
    void Function(SimpleFinPullProgress progress)? onProgress,
  }) async {
    _logger.log('connectWithSetupToken starting');
    final accessUrl = await _client.claimAccessUrl(setupToken);
    await _accessStore.save(accessUrl);
    _logger.log('Access URL saved; starting full-history pull');
    final result = await pull(fullHistory: true, onProgress: onProgress);
    return SimpleFinPullResult(
      accountCount: result.accountCount,
      transactionCount: result.transactionCount,
      errors: result.errors,
      accessUrl: accessUrl,
    );
  }

  Future<SimpleFinPullResult> pull({
    bool fullHistory = false,
    void Function(SimpleFinPullProgress progress)? onProgress,
  }) async {
    final accessUrl = await _requireAccessUrl();
    final now = DateTime.now().toUtc();
    final lastPull = await _simpleFinPullHistory.lastSuccessfulPullAt();
    final newlyInsertedByAccountExternalId =
        <String, List<SimpleFinPulledTransaction>>{};
    final outcomes = SimpleFinPullOutcomeAccumulator();
    final kind = fullHistory || lastPull == null
        ? SimpleFinPullKind.full
        : SimpleFinPullKind.incremental;

    _logger.log(
      'pull kind=$kind fullHistory=$fullHistory '
      'lastPull=$lastPull fromEnv=${_accessStore.isConfiguredInEnv}',
    );

    final pullId = await _simpleFinPullHistory.beginPull(
      kind: kind,
      startedAt: now,
    );
    final knownBanks = SimpleFinBankTarget.fromLocalAccounts(
      await _accountsRepository.listAccounts(),
    );

    var rulesRun = false;
    try {
      final pullResult = kind == SimpleFinPullKind.full
          ? await _pullFullHistory(
              accessUrl: accessUrl,
              now: now,
              onProgress: onProgress,
              newlyInsertedByAccountExternalId:
                  newlyInsertedByAccountExternalId,
              outcomes: outcomes,
              knownBanks: knownBanks,
            )
          : await _pullSinceLastPull(
              accessUrl: accessUrl,
              lastPull: lastPull!,
              now: now,
              onProgress: onProgress,
              newlyInsertedByAccountExternalId:
                  newlyInsertedByAccountExternalId,
              outcomes: outcomes,
              knownBanks: knownBanks,
            );

      final accountDrafts = outcomes.drafts;
      final pulledAccountCount = accountDrafts.isNotEmpty
          ? accountDrafts.length
          : newlyInsertedByAccountExternalId.length;
      await _simpleFinPullHistory.finishPullSuccess(
        pullId: pullId,
        finishedAt: now,
        accountCount: pulledAccountCount,
        transactionCount: pullResult.transactionCount,
        errors: pullResult.errors,
        accounts: accountDrafts,
      );

      _logger.log(
        'Pulled $pulledAccountCount accounts in this run '
        '(${(await _accountsRepository.listAccounts()).length} total locally), '
        '${pullResult.transactionCount} transactions, '
        '${pullResult.errors.length} bridge errors',
      );

      final rulesRerun = await _categorizer.recategorizeAll();
      rulesRun = true;
      final result = SimpleFinPullResult(
        accountCount: pulledAccountCount,
        transactionCount: pullResult.transactionCount,
        errors: pullResult.errors,
        rulesRerun: rulesRerun,
      );
      onProgress?.call(
        SimpleFinPullProgress.finished(
          accountCount: result.accountCount,
          transactionCount: result.transactionCount,
          errors: result.errors,
        ),
      );
      return result;
    } catch (error) {
      await _simpleFinPullHistory.finishPullFailed(
        pullId: pullId,
        finishedAt: DateTime.now().toUtc(),
        message: '$error',
        accounts: outcomes.drafts,
      );
      // Rows written before the failure still need their categories.
      if (!rulesRun) await _categorizer.recategorizeAll();
      rethrow;
    }
  }

  Future<void> disconnect({required bool wipeLocalData}) async {
    await _accessStore.clear();
    await _simpleFinPullHistory.clear();
    if (wipeLocalData) {
      await _accountsRepository.deleteAll();
    }
  }

  Future<Uri> _requireAccessUrl() async {
    final accessUrl = await _accessStore.read();
    if (accessUrl == null) {
      throw SimpleFinFetchException('No SimpleFIN connection. Connect first.');
    }
    return accessUrl;
  }

  Future<SimpleFinWindowIngestResult> _pullFullHistory({
    required Uri accessUrl,
    required DateTime now,
    void Function(SimpleFinPullProgress progress)? onProgress,
    required Map<String, List<SimpleFinPulledTransaction>>
    newlyInsertedByAccountExternalId,
    required SimpleFinPullOutcomeAccumulator outcomes,
    required List<SimpleFinBankTarget> knownBanks,
  }) async {
    final windows = SimpleFinPullWindows.fullHistory(now);
    var transactionCount = 0;
    final aggregatedErrors = <SimpleFinError>[];

    for (var index = 0; index < windows.length; index++) {
      final window = windows[index];
      _logger.log(
        'History window #${index + 1} '
        '${window.start.toIso8601String()} → ${window.end.toIso8601String()}',
      );
      final SimpleFinWindowIngestResult result;
      try {
        result = await _ingester.ingest(
          accessUrl: accessUrl,
          window: window,
          syncedAt: now,
          outcomes: outcomes,
          newlyInsertedByAccountExternalId: newlyInsertedByAccountExternalId,
          onProgress: onProgress,
          windowIndex: index + 1,
          windowCount: windows.length,
          knownBanks: knownBanks,
        );
      } on SimpleFinFetchException catch (error) {
        if (!error.isRateLimited) rethrow;
        // Windows run newest first, so what is missing is the oldest
        // history; stop instead of hammering a throttled bridge.
        aggregatedErrors.add(
          SimpleFinError(
            code: 'rateLimited',
            message:
                'SimpleFIN rate-limited the pull; history before '
                '${window.end.toIso8601String().substring(0, 10)} was not '
                'fetched. Try a full-history pull again later.',
          ),
        );
        break;
      }
      transactionCount += result.transactionCount;
      aggregatedErrors.addAll(result.errors);
    }

    return SimpleFinWindowIngestResult(
      transactionCount: transactionCount,
      errors: aggregatedErrors,
    );
  }

  Future<SimpleFinWindowIngestResult> _pullSinceLastPull({
    required Uri accessUrl,
    required DateTime lastPull,
    required DateTime now,
    void Function(SimpleFinPullProgress progress)? onProgress,
    required Map<String, List<SimpleFinPulledTransaction>>
    newlyInsertedByAccountExternalId,
    required SimpleFinPullOutcomeAccumulator outcomes,
    required List<SimpleFinBankTarget> knownBanks,
  }) async {
    final window = SimpleFinPullWindows.sinceLastPull(
      lastPull: lastPull,
      now: now,
    );
    _logger.log(
      'Incremental window '
      '${window.start.toIso8601String()} → ${window.end.toIso8601String()}',
    );
    return _ingester.ingest(
      accessUrl: accessUrl,
      window: window,
      syncedAt: now,
      outcomes: outcomes,
      newlyInsertedByAccountExternalId: newlyInsertedByAccountExternalId,
      onProgress: onProgress,
      knownBanks: knownBanks,
    );
  }
}

final pullSimpleFinTransactionsProvider =
    FutureProvider<PullSimpleFinTransactions>((ref) async {
      return PullSimpleFinTransactions(
        client: ref.watch(simpleFinClientProvider),
        accessStore: ref.watch(simpleFinAccessStoreProvider),
        accountsRepository: await ref.watch(accountsRepositoryProvider.future),
        snapshotsRepository: await ref.watch(
          accountBalanceSnapshotsRepositoryProvider.future,
        ),
        transactionsRepository: await ref.watch(
          transactionsRepositoryProvider.future,
        ),
        simpleFinPullHistory: await ref.watch(
          simpleFinPullHistoryProvider.future,
        ),
        categorizer: await ref.watch(categorizerProvider.future),
      );
    });
