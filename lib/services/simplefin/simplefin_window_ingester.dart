import 'package:spend_trends/services/simplefin/simplefin_account_mapper.dart';
import 'package:spend_trends/services/simplefin/simplefin_bank_target.dart';
import 'package:spend_trends/services/simplefin/simplefin_client.dart';
import 'package:spend_trends/services/simplefin/simplefin_models.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_outcome_accumulator.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_progress.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_windows.dart';
import 'package:spend_trends/services/simplefin/simplefin_transaction_mapper.dart';
import 'package:ethan_utils/ethan_utils.dart';

const _logger = ELogger('SimpleFinWindowIngester');

class const SimpleFinWindowIngestResult({
  required final int transactionCount,
  required final List<SimpleFinError> errors,
});

/// Fetches one date window from SimpleFIN and persists accounts/transactions.
///
/// Known banks download at the same time. A balances-only catalog runs in
/// parallel so a bank linked since the last pull is still fetched.
class SimpleFinWindowIngester({
  required final SimpleFinClient _client,
  required final SimpleFinAccountMapper _accountMapper,
  required final SimpleFinTransactionMapper _transactionMapper,
}) {
  Future<SimpleFinWindowIngestResult> ingest({
    required Uri accessUrl,
    required SimpleFinDateWindow window,
    required DateTime syncedAt,
    required SimpleFinPullOutcomeAccumulator outcomes,
    required Map<String, List<SimpleFinPulledTransaction>>
    newlyInsertedByAccountExternalId,
    void Function(SimpleFinPullProgress progress)? onProgress,
    int? windowIndex,
    int? windowCount,
    List<SimpleFinBankTarget> knownBanks = const [],
  }) async {
    onProgress?.call(
      SimpleFinPullProgress.fetching(
        windowStart: window.start,
        windowEnd: window.end,
        windowIndex: windowIndex,
        windowCount: windowCount,
      ),
    );

    try {
      return await _ingestBanks(
        accessUrl: accessUrl,
        window: window,
        syncedAt: syncedAt,
        outcomes: outcomes,
        newlyInsertedByAccountExternalId: newlyInsertedByAccountExternalId,
        onProgress: onProgress,
        knownBanks: knownBanks,
      );
    } catch (error, stackTrace) {
      _logger.error(
        'Window fetch failed '
        '${window.start.toIso8601String()} → ${window.end.toIso8601String()}',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<SimpleFinWindowIngestResult> _ingestBanks({
    required Uri accessUrl,
    required SimpleFinDateWindow window,
    required DateTime syncedAt,
    required SimpleFinPullOutcomeAccumulator outcomes,
    required Map<String, List<SimpleFinPulledTransaction>>
    newlyInsertedByAccountExternalId,
    required void Function(SimpleFinPullProgress progress)? onProgress,
    required List<SimpleFinBankTarget> knownBanks,
  }) async {
    if (knownBanks.isNotEmpty) {
      _announceBanks(knownBanks, onProgress);
    }
    final banks = knownBanks.isNotEmpty
        ? knownBanks
        : await _discoverBanks(accessUrl: accessUrl, window: window);
    if (banks.isEmpty) {
      return _ingestUnsplit(
        accessUrl: accessUrl,
        window: window,
        syncedAt: syncedAt,
        outcomes: outcomes,
        newlyInsertedByAccountExternalId: newlyInsertedByAccountExternalId,
        onProgress: onProgress,
      );
    }
    if (knownBanks.isEmpty) {
      _announceBanks(banks, onProgress);
    }

    final tally = _WindowIngestTally();
    final pulling = <String, Future<void>>{};

    Future<void> pullBank(SimpleFinBankTarget bank) {
      final previous = pulling[bank.connectionId] ?? Future<void>.value();
      final next = previous.then(
        (_) => _fetchAndPersistBank(
          accessUrl: accessUrl,
          window: window,
          syncedAt: syncedAt,
          bank: bank,
          outcomes: outcomes,
          newlyInsertedByAccountExternalId: newlyInsertedByAccountExternalId,
          onProgress: onProgress,
          tally: tally,
        ),
      );
      pulling[bank.connectionId] = next;
      return next;
    }

    final knownPulls = [for (final bank in banks) pullBank(bank)];
    final discovery = knownBanks.isEmpty
        ? Future<void>.value()
        : _pullBanksDiscoveredLater(
            accessUrl: accessUrl,
            window: window,
            knownBanks: banks,
            onProgress: onProgress,
            pullBank: pullBank,
            tally: tally,
          );
    await Future.wait([...knownPulls, discovery]);

    if (tally.everyBankFailed) {
      throw SimpleFinFetchException(
        tally.firstFailure ?? 'Every bank failed to load.',
      );
    }

    return SimpleFinWindowIngestResult(
      transactionCount: tally.transactionCount,
      errors: tally.errors,
    );
  }

  Future<List<SimpleFinBankTarget>> _discoverBanks({
    required Uri accessUrl,
    required SimpleFinDateWindow window,
  }) async {
    final catalog = await _client.fetchAccounts(
      accessUrl: accessUrl,
      start: window.start,
      end: window.end,
      pending: true,
      balancesOnly: true,
    );
    return SimpleFinBankTarget.fromAccountSet(catalog);
  }

  Future<void> _pullBanksDiscoveredLater({
    required Uri accessUrl,
    required SimpleFinDateWindow window,
    required List<SimpleFinBankTarget> knownBanks,
    required void Function(SimpleFinPullProgress progress)? onProgress,
    required Future<void> Function(SimpleFinBankTarget bank) pullBank,
    required _WindowIngestTally tally,
  }) async {
    final SimpleFinAccountSet catalog;
    try {
      catalog = await _client.fetchAccounts(
        accessUrl: accessUrl,
        start: window.start,
        end: window.end,
        pending: true,
        balancesOnly: true,
      );
    } on SimpleFinFetchException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 402) rethrow;
      tally.errors.add(
        SimpleFinError(code: 'fetch', message: error.message),
      );
      return;
    }
    tally.errors.addAll(catalog.errors);
    final fetchingIds = {
      for (final bank in knownBanks) ...bank.accountIds,
    };
    final extras = SimpleFinBankTarget.notYetFetching(
      accountSet: catalog,
      fetchingIds: fetchingIds,
    );
    if (extras.isEmpty) return;
    for (final bank in extras) {
      _emitBank(
        onProgress,
        SimpleFinBankLoad(connectionId: bank.connectionId, name: bank.name),
      );
    }
    await Future.wait([for (final bank in extras) pullBank(bank)]);
  }

  Future<SimpleFinWindowIngestResult> _ingestUnsplit({
    required Uri accessUrl,
    required SimpleFinDateWindow window,
    required DateTime syncedAt,
    required SimpleFinPullOutcomeAccumulator outcomes,
    required Map<String, List<SimpleFinPulledTransaction>>
    newlyInsertedByAccountExternalId,
    required void Function(SimpleFinPullProgress progress)? onProgress,
  }) async {
    const bank = SimpleFinBankTarget(
      connectionId: 'simplefin',
      name: 'SimpleFIN',
      accountIds: [],
    );
    _announceBanks([bank], onProgress);
    final tally = _WindowIngestTally();
    await _fetchAndPersistBank(
      accessUrl: accessUrl,
      window: window,
      syncedAt: syncedAt,
      bank: bank,
      outcomes: outcomes,
      newlyInsertedByAccountExternalId: newlyInsertedByAccountExternalId,
      onProgress: onProgress,
      tally: tally,
      restrictToRequestedIds: false,
    );
    if (tally.everyBankFailed) {
      throw SimpleFinFetchException(
        tally.firstFailure ?? 'SimpleFIN fetch failed.',
      );
    }
    return SimpleFinWindowIngestResult(
      transactionCount: tally.transactionCount,
      errors: tally.errors,
    );
  }

  Future<void> _fetchAndPersistBank({
    required Uri accessUrl,
    required SimpleFinDateWindow window,
    required DateTime syncedAt,
    required SimpleFinBankTarget bank,
    required SimpleFinPullOutcomeAccumulator outcomes,
    required Map<String, List<SimpleFinPulledTransaction>>
    newlyInsertedByAccountExternalId,
    required void Function(SimpleFinPullProgress progress)? onProgress,
    required _WindowIngestTally tally,
    bool restrictToRequestedIds = true,
  }) async {
    tally.attemptedBanks += 1;
    _emitBank(
      onProgress,
      SimpleFinBankLoad(
        connectionId: bank.connectionId,
        name: bank.name,
        phase: SimpleFinBankLoadPhase.receiving,
      ),
    );
    try {
      final accountSet = await _client.fetchAccounts(
        accessUrl: accessUrl,
        start: window.start,
        end: window.end,
        pending: true,
        accountIds: bank.accountIds,
        onBytes: (bytesReceived, contentLength) {
          _emitBank(
            onProgress,
            SimpleFinBankLoad(
              connectionId: bank.connectionId,
              name: bank.name,
              phase: SimpleFinBankLoadPhase.receiving,
              bytesReceived: bytesReceived,
              contentLength: contentLength,
            ),
          );
        },
      );
      _emitBank(
        onProgress,
        SimpleFinBankLoad(
          connectionId: bank.connectionId,
          name: bank.name,
          phase: SimpleFinBankLoadPhase.saving,
          bytesReceived: 1,
          contentLength: 1,
        ),
      );
      final requestedIds = bank.accountIds.toSet();
      final accounts = [
        for (final account in accountSet.accounts)
          if (!restrictToRequestedIds || requestedIds.contains(account.id))
            account,
      ];
      tally.transactionCount += await _persistAccounts(
        accounts: accounts,
        errors: accountSet.errors,
        syncedAt: syncedAt,
        outcomes: outcomes,
        newlyInsertedByAccountExternalId: newlyInsertedByAccountExternalId,
        onProgress: onProgress,
      );
      tally.errors.addAll(accountSet.errors);
      _emitBank(
        onProgress,
        SimpleFinBankLoad(
          connectionId: bank.connectionId,
          name: bank.name,
          phase: SimpleFinBankLoadPhase.done,
        ),
      );
    } on SimpleFinFetchException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 402) rethrow;
      tally.failedBanks += 1;
      tally.firstFailure ??= error.message;
      tally.errors.add(
        SimpleFinError(code: 'fetch', message: '${bank.name}: ${error.message}'),
      );
      _emitBank(
        onProgress,
        SimpleFinBankLoad(
          connectionId: bank.connectionId,
          name: bank.name,
          phase: SimpleFinBankLoadPhase.failed,
          errorMessage: error.message,
        ),
      );
    }
  }

  Future<int> _persistAccounts({
    required List<SimpleFinAccount> accounts,
    required List<SimpleFinError> errors,
    required DateTime syncedAt,
    required SimpleFinPullOutcomeAccumulator outcomes,
    required Map<String, List<SimpleFinPulledTransaction>>
    newlyInsertedByAccountExternalId,
    required void Function(SimpleFinPullProgress progress)? onProgress,
  }) async {
    final authErrors = errors.where((error) => error.isAuthFailure);
    var transactionCount = 0;
    for (var index = 0; index < accounts.length; index++) {
      final remoteAccount = accounts[index];
      final localId = await _accountMapper.upsertFromRemote(
        remoteAccount: remoteAccount,
        authErrors: authErrors,
        syncedAt: syncedAt,
      );
      final newlyInserted = await _transactionMapper.upsertFromRemote(
        remoteAccount: remoteAccount,
        localAccountId: localId,
        syncedAt: syncedAt,
      );
      transactionCount += newlyInserted.length;
      final accountTransactions = newlyInsertedByAccountExternalId.putIfAbsent(
        remoteAccount.id,
        () => [],
      )..addAll(newlyInserted);
      accountTransactions.sort(
        (left, right) => right.postedAt.compareTo(left.postedAt),
      );
      outcomes.recordAccount(
        remoteAccount: remoteAccount,
        localAccountId: localId,
        newlyInsertedCount: newlyInserted.length,
        authErrors: authErrors,
        bridgeErrors: errors,
      );
      onProgress?.call(
        SimpleFinPullProgress.accountLoaded(
          accountExternalId: remoteAccount.id,
          accountLabel: SimpleFinAccountMapper.labelFor(remoteAccount),
          transactionCount: accountTransactions.length,
          transactions: List<SimpleFinPulledTransaction>.of(accountTransactions),
          accountsDone: index + 1,
          accountsTotal: accounts.length,
        ),
      );
    }
    outcomes.recordErrorOnlyAccounts(errors);
    return transactionCount;
  }

  void _announceBanks(
    List<SimpleFinBankTarget> banks,
    void Function(SimpleFinPullProgress progress)? onProgress,
  ) {
    onProgress?.call(
      SimpleFinPullProgress.banksWaiting(
        banks: [
          for (final bank in banks)
            SimpleFinBankLoad(connectionId: bank.connectionId, name: bank.name),
        ],
      ),
    );
  }

  void _emitBank(
    void Function(SimpleFinPullProgress progress)? onProgress,
    SimpleFinBankLoad bank,
  ) {
    onProgress?.call(SimpleFinPullProgress.bankLoad(bank: bank));
  }
}

class _WindowIngestTally() {
  int transactionCount = 0;
  int attemptedBanks = 0;
  int failedBanks = 0;
  String? firstFailure;
  final List<SimpleFinError> errors = [];

  bool get everyBankFailed =>
      attemptedBanks > 0 && failedBanks == attemptedBanks;
}
