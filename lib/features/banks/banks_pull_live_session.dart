import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/rule_match_index.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_progress.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

import 'banks_providers.dart';

class BanksPullAccountProgress({
  required final String externalId,
  required var String label,
  required var List<SimpleFinPulledTransaction> transactions,
  required var bool done,
}) {
  int get transactionCount => transactions.length;
}

class const BanksPullLiveSessionState({
  required final DateTime startedAt,
  required final String statusLine,
  final String? queryWindowLine,
  final List<BanksPullAccountProgress> accounts = const [],
  final List<SimpleFinBankLoad> banks = const [],
  final int? windowIndex,
  final int? windowCount,
  final bool finished = false,
  final bool failed = false,
  final bool categorizationReady = false,
  final String? errorMessage,
  final int? overallAccounts,
  final int? overallTransactions,
  final int bridgeWarningCount = 0,
  final Duration displayedElapsed = Duration.zero,
  final DateTime? finishedAt,
}) {
  BanksPullLiveSessionState copyWith({
    String? statusLine,
    String? queryWindowLine,
    List<BanksPullAccountProgress>? accounts,
    List<SimpleFinBankLoad>? banks,
    int? windowIndex,
    int? windowCount,
    bool? finished,
    bool? failed,
    bool? categorizationReady,
    String? errorMessage,
    int? overallAccounts,
    int? overallTransactions,
    int? bridgeWarningCount,
    Duration? displayedElapsed,
    DateTime? finishedAt,
  }) {
    return BanksPullLiveSessionState(
      startedAt: startedAt,
      statusLine: statusLine ?? this.statusLine,
      queryWindowLine: queryWindowLine ?? this.queryWindowLine,
      accounts: accounts ?? this.accounts,
      banks: banks ?? this.banks,
      windowIndex: windowIndex ?? this.windowIndex,
      windowCount: windowCount ?? this.windowCount,
      finished: finished ?? this.finished,
      failed: failed ?? this.failed,
      categorizationReady: categorizationReady ?? this.categorizationReady,
      errorMessage: errorMessage ?? this.errorMessage,
      overallAccounts: overallAccounts ?? this.overallAccounts,
      overallTransactions: overallTransactions ?? this.overallTransactions,
      bridgeWarningCount: bridgeWarningCount ?? this.bridgeWarningCount,
      displayedElapsed: displayedElapsed ?? this.displayedElapsed,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}

final banksPullLiveSessionProvider =
    NotifierProvider<BanksPullLiveSession, BanksPullLiveSessionState?>(
      BanksPullLiveSession.new,
    );

/// Ephemeral live state for the in-progress or just-finished pull on Banks.
class BanksPullLiveSession() extends Notifier<BanksPullLiveSessionState?> {
  final Stopwatch _elapsed = Stopwatch();
  final Map<String, DateTime> _lastBankByteEmit = {};
  Timer? _ticker;

  @override
  BanksPullLiveSessionState? build() => null;

  Future<void> runPull(
    Future<void> Function(
      void Function(SimpleFinPullProgress progress) onProgress,
    )
    action,
  ) async {
    _ticker?.cancel();
    _lastBankByteEmit.clear();
    _elapsed
      ..reset()
      ..start();
    state = BanksPullLiveSessionState(
      startedAt: DateTime.now(),
      statusLine: 'Starting…',
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final session = state;
      if (session == null || session.finished) return;
      state = session.copyWith(displayedElapsed: _elapsed.elapsed);
    });

    try {
      await action(_mergeLivePullProgress);
      final session = state;
      if (session == null) return;
      state = session.copyWith(statusLine: 'Applying category rules…');
      await _enrichCategorization();
      final updated = state;
      if (updated == null) return;
      _stopTicker();
      final finishedAt = DateTime.now().toUtc();
      state = updated.copyWith(
        finished: true,
        categorizationReady: true,
        displayedElapsed: _elapsed.elapsed,
        finishedAt: finishedAt,
        statusLine: updated.failed
            ? updated.statusLine
            : 'Completed in ${_elapsed.elapsed.formattedSeconds}',
      );
      ref.invalidate(simpleFinPullHistoryListProvider);
    } catch (error) {
      final session = state;
      if (session == null) return;
      _stopTicker();
      final finishedAt = DateTime.now().toUtc();
      state = session.copyWith(
        failed: true,
        finished: true,
        displayedElapsed: _elapsed.elapsed,
        finishedAt: finishedAt,
        errorMessage: '$error',
        statusLine: 'Failed after ${_elapsed.elapsed.formattedSeconds}',
      );
      ref.invalidate(simpleFinPullHistoryListProvider);
    }
  }

  void _mergeLivePullProgress(SimpleFinPullProgress progress) {
    final session = state;
    if (session == null) return;

    final accounts = [...session.accounts];
    var banks = [...session.banks];
    var statusLine = session.statusLine;
    String? queryWindowLine = session.queryWindowLine;
    int? overallAccounts = session.overallAccounts;
    int? overallTransactions = session.overallTransactions;
    var bridgeWarningCount = session.bridgeWarningCount;
    var windowIndex = session.windowIndex;
    var windowCount = session.windowCount;

    switch (progress.phase) {
      case SimpleFinPullProgressPhase.fetching:
        queryWindowLine = _formatQueryWindow(
          start: progress.windowStart!,
          end: progress.windowEnd!,
        );
        windowIndex = progress.windowIndex ?? windowIndex;
        windowCount = progress.windowCount ?? windowCount;
        if (banks.isEmpty) statusLine = 'Finding banks…';
        if (windowIndex != null && windowCount != null) {
          statusLine = banks.isEmpty
              ? 'Finding banks — window $windowIndex of $windowCount…'
              : '${_pullingStatus(banks)} Window $windowIndex of $windowCount.';
        }
        for (final account in accounts) {
          account.done = false;
        }
      case SimpleFinPullProgressPhase.banksWaiting:
        banks = [...progress.banks];
        statusLine = _pullingStatus(banks);
        if (windowIndex != null && windowCount != null) {
          statusLine =
              '${_pullingStatus(banks)} Window $windowIndex of $windowCount.';
        }
      case SimpleFinPullProgressPhase.bankLoad:
        final load = progress.banks.single;
        if (_shouldSkipBankBytes(load)) return;
        banks = _withBankLoad(banks, load);
        statusLine = _pullingStatus(banks);
        if (windowIndex != null && windowCount != null) {
          statusLine = '$statusLine Window $windowIndex of $windowCount.';
        }
      case SimpleFinPullProgressPhase.accountLoaded:
        final externalId = progress.accountExternalId!;
        final existingIndex = accounts.indexWhere(
          (row) => row.externalId == externalId,
        );
        if (existingIndex >= 0) {
          accounts[existingIndex].transactions = progress.accountTransactions;
          accounts[existingIndex].label = progress.accountLabel!;
          accounts[existingIndex].done = true;
        } else {
          accounts.add(
            BanksPullAccountProgress(
              externalId: externalId,
              label: progress.accountLabel!,
              transactions: progress.accountTransactions,
              done: true,
            ),
          );
        }
      case SimpleFinPullProgressPhase.finished:
        overallAccounts = progress.finishedAccountCount;
        overallTransactions = progress.finishedTransactionCount;
        bridgeWarningCount = progress.errors.length;
        statusLine = 'Applying category rules…';
    }

    state = session.copyWith(
      statusLine: statusLine,
      queryWindowLine: queryWindowLine,
      accounts: accounts,
      banks: banks,
      windowIndex: windowIndex,
      windowCount: windowCount,
      overallAccounts: overallAccounts,
      overallTransactions: overallTransactions,
      bridgeWarningCount: bridgeWarningCount,
    );
  }

  bool _shouldSkipBankBytes(SimpleFinBankLoad bank) {
    if (bank.phase != SimpleFinBankLoadPhase.receiving) return false;
    if (bank.bytesReceived == 0) return false;
    final now = DateTime.now();
    final lastEmit = _lastBankByteEmit[bank.connectionId];
    if (lastEmit != null && now.difference(lastEmit).inMilliseconds < 80) {
      return true;
    }
    _lastBankByteEmit[bank.connectionId] = now;
    return false;
  }

  List<SimpleFinBankLoad> _withBankLoad(
    List<SimpleFinBankLoad> banks,
    SimpleFinBankLoad load,
  ) {
    final next = [...banks];
    final existingIndex = next.indexWhere(
      (bank) => bank.connectionId == load.connectionId,
    );
    if (existingIndex >= 0) {
      next[existingIndex] = load;
      return next;
    }
    next.add(load);
    next.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return next;
  }

  static String _pullingStatus(List<SimpleFinBankLoad> banks) {
    if (banks.isEmpty) return 'Finding banks…';
    final stillPulling = banks
        .where(
          (bank) =>
              bank.phase != SimpleFinBankLoadPhase.done &&
              bank.phase != SimpleFinBankLoadPhase.failed,
        )
        .length;
    final bankWord = banks.length == 1 ? 'bank' : 'banks';
    return 'Still pulling $stillPulling of ${banks.length} $bankWord';
  }

  Future<void> _enrichCategorization() async {
    final session = state;
    if (session == null) return;

    final pulledIds = <String>{
      for (final account in session.accounts)
        for (final transaction in account.transactions) transaction.id,
    };
    if (pulledIds.isEmpty) return;

    final transactionsRepository = await ref.read(
      transactionsRepositoryProvider.future,
    );
    final categoriesRepository = await ref.read(
      categoriesRepositoryProvider.future,
    );
    final bankTransactions = await transactionsRepository.listAll();
    final byId = {
      for (final transaction in bankTransactions)
        if (pulledIds.contains(transaction.id)) transaction.id: transaction,
    };
    final categoryNameById = {
      for (final category in await categoriesRepository.listAll())
        category.id: category.name,
    };
    final ruleMatchIndex = RuleMatchIndex(
      await categoriesRepository.listRules(),
    );

    final accounts = [...session.accounts];
    for (final account in accounts) {
      account.transactions = [
        for (final pulled in account.transactions)
          _categorizedPull(
            pulled: pulled,
            bankTransaction: byId[pulled.id],
            categoryNameById: categoryNameById,
            ruleMatchIndex: ruleMatchIndex,
          ),
      ];
    }
    state = session.copyWith(accounts: accounts, categorizationReady: true);
  }

  static SimpleFinPulledTransaction _categorizedPull({
    required SimpleFinPulledTransaction pulled,
    required BankTransaction? bankTransaction,
    required Map<String, String> categoryNameById,
    required RuleMatchIndex ruleMatchIndex,
  }) {
    if (bankTransaction == null) return pulled;
    final explaining = ruleMatchIndex.explainingRule(bankTransaction);
    if (explaining != null) {
      return pulled.withCategorization(
        categoryId: explaining.categoryId,
        categoryName: categoryNameById[explaining.categoryId],
        matchedRulePattern: explaining.pattern,
      );
    }
    final categoryId = bankTransaction.effectiveCategoryId;
    if (categoryId == null) {
      return pulled.withCategorization(
        categoryId: null,
        categoryName: null,
        matchedRulePattern: null,
      );
    }
    return pulled.withCategorization(
      categoryId: categoryId,
      categoryName: categoryNameById[categoryId],
      matchedRulePattern: null,
    );
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _elapsed.stop();
  }

  static String _formatQueryWindow({
    required DateTime start,
    required DateTime end,
  }) {
    final dayFormat = DateFormat.yMMMd();
    return 'Querying ${dayFormat.format(start.toLocal())} – '
        '${dayFormat.format(end.toLocal())}';
  }
}
