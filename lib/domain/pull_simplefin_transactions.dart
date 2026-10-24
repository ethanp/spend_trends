import 'package:spend_trends/services/simplefin/simplefin_access_store.dart';
import 'package:spend_trends/services/simplefin/simplefin_bank_target.dart';
import 'package:spend_trends/services/simplefin/simplefin_account_mapper.dart';
import 'package:spend_trends/services/simplefin/simplefin_client.dart';
import 'package:spend_trends/services/simplefin/simplefin_models.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_outcome_accumulator.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_progress.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_windows.dart';
import 'package:spend_trends/services/simplefin/simplefin_transaction_mapper.dart';
import 'package:spend_trends/services/simplefin/simplefin_window_ingester.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/simplefin_pull_history.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:ethan_utils/ethan_utils.dart';

const _logger = ELogger('PullSimpleFinTransactions');

/// Orchestrates SimpleFIN connect / pull / disconnect.
///
/// Window policy, remote→local mapping, outage journaling, and UI progress
/// DTOs live in dedicated modules under `services/simplefin/`.
class PullSimpleFinTransactions({
  required final SimpleFinClient _client,
  required final SimpleFinAccessStore _accessStore,
  required final AccountsRepository _accountsRepository,
  required TransactionsRepository transactionsRepository,
  required final SimpleFinPullHistory _simpleFinPullHistory,
}) {
  final SimpleFinWindowIngester _ingester = SimpleFinWindowIngester(
    client: _client,
    accountMapper: SimpleFinAccountMapper(
      accountsRepository: _accountsRepository,
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

      final result = SimpleFinPullResult(
        accountCount: pulledAccountCount,
        transactionCount: pullResult.transactionCount,
        errors: pullResult.errors,
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
      final result = await _ingester.ingest(
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
