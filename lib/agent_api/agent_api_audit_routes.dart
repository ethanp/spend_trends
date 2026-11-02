import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/agent_api/rule_change_request.dart';
import 'package:spend_trends/agent_api/transaction_query.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/cash_flow_breakdown.dart';
import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/remove_copilot_duplicates.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/settings/remove_copilot_duplicates_provider.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/account_balance_snapshots_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

/// Auditing where money went without scripting over raw rows: totals by any
/// grouping, a window's cash flow decomposed, notes on many rows at once,
/// balance history, and duplicate imports.
class const AgentApiAuditRoutes({required final ProviderContainer container}) {
  /// Mounted before the read routes so `/transactions/totals` is not taken
  /// for a transaction id.
  void mount(Router router) {
    router
      ..get('/transactions/totals', _transactionTotals)
      ..post('/transactions/notes', _noteTransactions)
      ..post('/transactions/remove', _removeTransactions)
      ..get('/cash-flow', _cashFlow)
      ..get('/accounts/<accountId>/balances', _accountBalances)
      ..get('/duplicates', _duplicates)
      ..post('/duplicates/remove', _removeDuplicates);
  }

  /// `?groupBy=category|area|merchant|account|accountKind|month|rule` plus
  /// any `/transactions` filter. Groups are largest first (months in order);
  /// `limit` caps the number of groups.
  Future<Response> _transactionTotals(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final parameters = request.url.queryParameters;
    final grouping = _TransactionGrouping.values.byName(
      parameters['groupBy'] ?? _TransactionGrouping.category.name,
    );
    final query = TransactionQuery.fromQueryParameters(parameters);
    final matching = query.matchingTransactions(snapshot);
    final totalsByKey = <String, _GroupTotals>{};
    for (final transaction in matching) {
      final String key = grouping.keyOf(transaction, snapshot);
      totalsByKey
          .putIfAbsent(
            key,
            () => _GroupTotals(
              key: key,
              label: grouping.labelOf(key, transaction, snapshot),
            ),
          )
          .add(transaction.amountCents);
    }
    final groups = totalsByKey.values.toList()
      ..sort(
        grouping == _TransactionGrouping.month
            ? (left, right) => left.key.compareTo(right.key)
            : (left, right) =>
                  right.sumCents.abs().compareTo(left.sumCents.abs()),
      );
    return jsonOk({
      'groupBy': grouping.name,
      'matched': matching.length,
      'sumCents': matching.fold(
        0,
        (sum, transaction) => sum + transaction.amountCents,
      ),
      'groupCount': groups.length,
      'groups': [for (final group in groups.take(query.limit)) group.toJson()],
    });
  }

  /// `{ids?: [...], query?: {any /transactions filter}, note,
  /// mode?: append|replace, dryRun?}`. Append adds ` · note` unless the
  /// note is already there. Re-runs the rules over every noted row once, so
  /// a contains rule on the note phrase takes them; the report lists the
  /// category moves that caused.
  Future<Response> _noteTransactions(Request request) async {
    final body = await request.readJsonObject();
    final snapshot = await CategorizationSnapshot.load(container);
    final note = body.requiredString('note');
    final mode = _NoteMode.values.byName(
      body['mode'] as String? ?? _NoteMode.append.name,
    );
    final query = TransactionQuery.fromJson({
      ...(body['query'] as Map<String, dynamic>? ?? const {}),
      if (body['ids'] != null) 'ids': body['ids'],
      'limit': 1 << 30,
    });
    if (!query.narrows) {
      throw ArgumentError('Give "ids" or a narrowing "query".');
    }
    final matching = query.matchingTransactions(snapshot);
    final noteByTransactionId = {
      for (final transaction in matching)
        transaction.id: mode.notedText(existing: transaction.note, note: note),
    };
    final changedNoteById = {
      for (final transaction in matching)
        if (noteByTransactionId[transaction.id] != transaction.note?.trim())
          transaction.id: noteByTransactionId[transaction.id]!,
    };
    final preview = {
      'matched': matching.length,
      'notesChanged': changedNoteById.length,
      'sample': [
        for (final transaction in matching.take(20))
          {
            ...snapshot.transactionJson(transaction),
            'noteAfter': noteByTransactionId[transaction.id],
          },
      ],
    };
    if (body['dryRun'] == true) return jsonOk(preview);
    final Categorizer categorizer = await container.read(
      categorizerProvider.future,
    );
    final plan = await categorizer.setNotes(changedNoteById);
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({
      ...preview,
      'rulesRerun': RuleChangeReport(plan: plan, snapshot: snapshot).toJson(),
    });
  }

  /// `{ids, apply?}`. Previews the listed rows unless `apply` is true, then
  /// deletes exactly those. Ids only, never a filter, so a delete can't
  /// reach rows nobody looked at.
  Future<Response> _removeTransactions(Request request) async {
    final body = await request.readJsonObject();
    final ids = body.requiredStringList('ids').toSet();
    final snapshot = await CategorizationSnapshot.load(container);
    final found = [
      for (final transaction in snapshot.transactions)
        if (ids.contains(transaction.id)) transaction,
    ];
    final preview = {
      'requested': ids.length,
      'found': found.length,
      'missingIds': ids.difference({for (final row in found) row.id}).toList(),
      'sumCents': found.fold(0, (sum, row) => sum + row.amountCents),
      'rows': found.map(snapshot.transactionJson).toList(),
    };
    if (body['apply'] != true) return jsonOk(preview);
    final TransactionsRepository transactionsRepository = await container.read(
      transactionsRepositoryProvider.future,
    );
    for (final transaction in found) {
      await transactionsRepository.deleteTransaction(transaction.id);
    }
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({...preview, 'removed': found.length});
  }

  /// `?since=&until=` (default the last 365 days). Pay, the three areas,
  /// spending excluded from lifestyle costs, spending with no area, then
  /// where the rest went: transfers in and out of cash accounts by merchant
  /// and the cash balance change over the window.
  Future<Response> _cashFlow(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final parameters = request.url.queryParameters;
    final CalendarDay lastDay = parameters['until'] == null
        ? CalendarDay.today()
        : CalendarDay.fromDateTime(DateTime.parse(parameters['until']!));
    final CalendarDay firstDay = parameters['since'] == null
        ? lastDay.plusDays(-364)
        : CalendarDay.fromDateTime(DateTime.parse(parameters['since']!));
    final cashFlowBreakdown = CashFlowBreakdown(
      categories: snapshot.categories,
      accounts: snapshot.accounts,
    );
    final windowTotals = _CashFlowWindowTotals();
    for (final transaction in snapshot.transactions) {
      final CalendarDay day = transaction.postedDay;
      if (day.isBefore(firstDay) || day.isAfter(lastDay)) continue;
      windowTotals.add(
        transaction,
        cashFlowBreakdown.contributionOf(transaction),
        snapshot,
      );
    }
    final List<AccountBalanceSnapshot> balances = await (await container.read(
      accountBalanceSnapshotsRepositoryProvider.future,
    )).listAll();
    return jsonOk({
      'since': firstDay.isoDate,
      'until': lastDay.isoDate,
      ...windowTotals.toJson(),
      'cashBalances': _cashBalanceChange(
        snapshot: snapshot,
        balances: balances,
        firstDay: firstDay,
        lastDay: lastDay,
      ),
    });
  }

  /// Balance at the window's edges for each checking and savings account
  /// that counts toward net worth, from recorded snapshots.
  Map<String, Object?> _cashBalanceChange({
    required CategorizationSnapshot snapshot,
    required List<AccountBalanceSnapshot> balances,
    required CalendarDay firstDay,
    required CalendarDay lastDay,
  }) {
    final cashAccounts = [
      for (final account in snapshot.accounts)
        if (account.countsTowardNetWorth &&
            (account.kind == AccountKind.checking ||
                account.kind == AccountKind.savings))
          account,
    ];
    final rows = [
      for (final account in cashAccounts)
        {
          'account': account.displayNameWithInstitution,
          'startCents': _balanceOn(balances, account, firstDay.plusDays(-1)),
          'endCents': _balanceOn(balances, account, lastDay),
        },
    ];
    int sumOf(String key) =>
        rows.fold(0, (sum, row) => sum + ((row[key] as int?) ?? 0));
    return {
      'startCents': sumOf('startCents'),
      'endCents': sumOf('endCents'),
      'changeCents': sumOf('endCents') - sumOf('startCents'),
      'byAccount': rows,
    };
  }

  /// Latest recorded balance on or before [day], or null before any record.
  static int? _balanceOn(
    List<AccountBalanceSnapshot> balances,
    Account account,
    CalendarDay day,
  ) {
    AccountBalanceSnapshot? latest;
    for (final balance in balances) {
      if (balance.accountId != account.id || balance.recordedDay.isAfter(day)) {
        continue;
      }
      if (latest == null || balance.recordedDay.isAfter(latest.recordedDay)) {
        latest = balance;
      }
    }
    return latest?.balanceCents;
  }

  /// `?since=&until=&every=month|day` (default month: the last recorded
  /// balance in each month).
  Future<Response> _accountBalances(Request request, String accountId) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final account = snapshot.accountsById[accountId];
    if (account == null) return jsonError('No account $accountId', status: 404);
    final parameters = request.url.queryParameters;
    final since = parameters['since'];
    final until = parameters['until'];
    final everyDay = parameters['every'] == 'day';
    final List<AccountBalanceSnapshot> balances = await (await container.read(
      accountBalanceSnapshotsRepositoryProvider.future,
    )).listAll();
    final balanceByPeriod = <String, AccountBalanceSnapshot>{};
    for (final balance in balances) {
      if (balance.accountId != accountId) continue;
      final String day = balance.recordedDay.isoDate;
      if (since != null && day.compareTo(since) < 0) continue;
      if (until != null && day.compareTo(until) > 0) continue;
      balanceByPeriod[everyDay ? day : balance.recordedDay.yearMonthKey] =
          balance;
    }
    return jsonOk({
      'account': snapshot.accountJson(account),
      'every': everyDay ? 'day' : 'month',
      'balances': [
        for (final balance in balanceByPeriod.values)
          {
            'recordedOn': balance.recordedDay.isoDate,
            'balanceCents': balance.balanceCents,
          },
      ],
    });
  }

  /// What `POST /duplicates/remove` would delete: Copilot rows the linked
  /// live-feed account recorded again (up to 5 days apart), and repeats on
  /// one account.
  Future<Response> _duplicates(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final RemoveCopilotDuplicates remover = await container.read(
      removeCopilotDuplicatesProvider.future,
    );
    final duplicatesPlan = await remover.plan();
    Map<String, Object?> pairJson(CopilotDuplicate pair) => {
      'delete': snapshot.transactionJson(pair.duplicate),
      'keep': snapshot.transactionJson(pair.keeper),
    };
    int centsOf(List<CopilotDuplicate> pairs) =>
        pairs.fold(0, (sum, pair) => sum + pair.duplicate.amountCents);
    return jsonOk({
      'linkedCount': duplicatesPlan.linked.length,
      'linkedCents': centsOf(duplicatesPlan.linked),
      'sameAccountCount': duplicatesPlan.sameAccount.length,
      'sameAccountCents': centsOf(duplicatesPlan.sameAccount),
      'linked': duplicatesPlan.linked.map(pairJson).toList(),
      'sameAccount': duplicatesPlan.sameAccount.map(pairJson).toList(),
    });
  }

  /// `{linked?: bool, sameAccount?: bool}` (both default true). Deletes
  /// what `GET /duplicates` lists, keeping each duplicate's note on the row
  /// that stays. With both, the same as Settings → Remove duplicates.
  Future<Response> _removeDuplicates(Request request) async {
    final body = await request.readJsonObject();
    final RemoveCopilotDuplicates remover = await container.read(
      removeCopilotDuplicatesProvider.future,
    );
    final duplicatesPlan = await remover.plan();
    final result = await remover.remove(
      CopilotDuplicatesPlan(
        linked: body['linked'] == false ? const [] : duplicatesPlan.linked,
        sameAccount: body['sameAccount'] == false
            ? const []
            : duplicatesPlan.sameAccount,
        linkedAccountMasks: duplicatesPlan.linkedAccountMasks,
      ),
    );
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({
      'deletedCopilotCount': result.deletedCopilotCount,
      'deletedSameAccountCount': result.deletedSameAccountCount,
      'linkedAccountMasks': result.linkedAccountMasks,
    });
  }
}

enum _NoteMode() {
  append,
  replace;

  String notedText({required String? existing, required String note}) {
    final String current = existing.trimmedOrEmpty;
    if (this == _NoteMode.replace || current.isEmpty) return note;
    if (current.contains(note)) return current;
    return '$current · $note';
  }
}

enum _TransactionGrouping() {
  category,
  area,
  merchant,
  account,
  accountKind,
  month,
  rule;

  String keyOf(BankTransaction transaction, CategorizationSnapshot snapshot) =>
      switch (this) {
        _TransactionGrouping.category =>
          transaction.categoryId ?? TransactionQuery.uncategorizedCategoryId,
        _TransactionGrouping.area =>
          snapshot
                  .categoriesById[transaction.categoryId]
                  ?.consciousSpendingArea
                  ?.name ??
              TransactionQuery.noAreaName,
        _TransactionGrouping.merchant => transaction.normalizedMerchant,
        _TransactionGrouping.account => transaction.accountId,
        _TransactionGrouping.accountKind =>
          snapshot.accountsById[transaction.accountId]?.kind.name ?? 'unknown',
        _TransactionGrouping.month => transaction.postedDay.yearMonthKey,
        _TransactionGrouping.rule => transaction.categoryRuleId ?? 'none',
      };

  String labelOf(
    String key,
    BankTransaction transaction,
    CategorizationSnapshot snapshot,
  ) => switch (this) {
    _TransactionGrouping.category =>
      snapshot.categoriesById[transaction.categoryId]?.name ?? 'Uncategorized',
    _TransactionGrouping.area =>
      ConsciousSpendingArea.fromStorage(key)?.displayName ?? 'No area',
    _TransactionGrouping.account =>
      snapshot.accountsById[key]?.displayNameWithInstitution ?? key,
    _TransactionGrouping.rule => snapshot.rulesById[key]?.pattern ?? 'No rule',
    _TransactionGrouping.merchant ||
    _TransactionGrouping.accountKind ||
    _TransactionGrouping.month => key,
  };
}

class _GroupTotals({required final String key, required final String label}) {
  int count = 0;
  int sumCents = 0;
  int outflowCents = 0;
  int inflowCents = 0;

  void add(int amountCents) {
    count++;
    sumCents += amountCents;
    if (amountCents < 0) {
      outflowCents -= amountCents;
    } else {
      inflowCents += amountCents;
    }
  }

  Map<String, Object?> toJson() => {
    'key': key,
    'label': label,
    'count': count,
    'sumCents': sumCents,
    'outflowCents': outflowCents,
    'inflowCents': inflowCents,
  };
}

/// One window's [CashFlowContribution]s summed, plus the cash-account
/// transfers that fill no bucket, by merchant.
class _CashFlowWindowTotals() {
  int takeHomeCents = 0;
  int payrollContributionCents = 0;
  int excludedFromLifestyleCents = 0;
  int uncategorizedSpendingCents = 0;
  final Map<ConsciousSpendingArea, int> centsByArea = {
    for (final area in ConsciousSpendingArea.values) area: 0,
  };
  final Map<String, int> noAreaCentsByCategory = {};
  final Map<String, int> transferOutCentsByMerchant = {};
  final Map<String, int> transferInCentsByMerchant = {};

  void add(
    BankTransaction transaction,
    CashFlowContribution contribution,
    CategorizationSnapshot snapshot,
  ) {
    takeHomeCents += contribution.takeHomeCents;
    payrollContributionCents += contribution.payrollContributionCents;
    excludedFromLifestyleCents += contribution.excludedFromLifestyleCents;
    final area = contribution.area;
    if (area != null) {
      centsByArea[area] = centsByArea[area]! + contribution.areaCents;
    } else if (contribution.lifestyleSpendingCents != 0) {
      if (transaction.isUncategorized) {
        uncategorizedSpendingCents += contribution.lifestyleSpendingCents;
      } else {
        final String categoryName =
            snapshot.categoriesById[transaction.categoryId]?.name ??
            '${transaction.categoryId}';
        noAreaCentsByCategory.update(
          categoryName,
          (cents) => cents + contribution.lifestyleSpendingCents,
          ifAbsent: () => contribution.lifestyleSpendingCents,
        );
      }
    }
    if (contribution.transferCents == 0) return;
    final AccountKind? kind =
        snapshot.accountsById[transaction.accountId]?.kind;
    if (kind != AccountKind.checking && kind != AccountKind.savings) return;
    final transfersByMerchant = transaction.isOutflow
        ? transferOutCentsByMerchant
        : transferInCentsByMerchant;
    transfersByMerchant.update(
      transaction.normalizedMerchant,
      (cents) => cents + contribution.transferCents,
      ifAbsent: () => contribution.transferCents,
    );
  }

  int get payCents => takeHomeCents + payrollContributionCents;

  Map<String, Object?> toJson() {
    final int areaCents = centsByArea.values.fold(
      0,
      (sum, cents) => sum + cents,
    );
    final int noAreaCents = noAreaCentsByCategory.values.fold(
      0,
      (sum, cents) => sum + cents,
    );
    List<Map<String, Object?>> largestFirst(Map<String, int> centsByName) => [
      for (final entry
          in centsByName.entries.toList()
            ..sort((left, right) => right.value.compareTo(left.value)))
        {'name': entry.key, 'cents': entry.value},
    ];
    return {
      'payCents': payCents,
      'takeHomeCents': takeHomeCents,
      'payrollContributionCents': payrollContributionCents,
      'areas': {
        for (final entry in centsByArea.entries) entry.key.name: entry.value,
      },
      'excludedFromLifestyleCents': excludedFromLifestyleCents,
      'uncategorizedSpendingCents': uncategorizedSpendingCents,
      'noAreaSpending': largestFirst(noAreaCentsByCategory),
      'unaccountedCents':
          payCents -
          areaCents -
          excludedFromLifestyleCents -
          uncategorizedSpendingCents -
          noAreaCents,
      'transfersOutOfCash': largestFirst(transferOutCentsByMerchant),
      'transfersIntoCash': largestFirst(transferInCentsByMerchant),
    };
  }
}
