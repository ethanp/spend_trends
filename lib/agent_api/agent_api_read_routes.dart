import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/agent_api/live_retirement_projection.dart';
import 'package:spend_trends/agent_api/rule_change_request.dart';
import 'package:spend_trends/agent_api/transaction_query.dart';
import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';

/// Read-only audit routes: overview, categories, accounts, rules,
/// transactions, per-merchant rollups, and rule dry runs.
class const AgentApiReadRoutes({required final ProviderContainer container}) {
  static const _categorizationGuide = '''
Spend Trends tracks categorized bank activity for one person who budgets with
Ramit Sethi's Conscious Spending Plan toward a FIRE timeline.

Category roles:
- spend: real consumption. Each spend category belongs to one conscious
  spending area (fixedCosts, guiltFree) measured as a share of take-home
  pay. The user has no savings-goals bucket: planned expenses come straight
  from paychecks, so the plan is three numbers (fixedCosts, investments,
  guiltFree).
- income (Income): take-home pay. Paychecks, plus RSU sale proceeds once
  they reach a cash account ("Funds Transfer From Brokerage"); RSUs are
  compensation. Income on investment accounts (dividends, sales still in the
  brokerage) is a return, not take-home pay.
- investments (Investments): net money put into investments. On cash
  accounts, deposits to a brokerage/crypto add and money back from it
  subtracts; on investment accounts, 401(k)/HSA payroll contributions add.
  Use it for the cash side of a deposit; the brokerage side stays Transfer.
  RSU sale proceeds are Income, not an Investments withdrawal.
- transfer: money moving between the user's own accounts (card payments,
  brokerage moves, buys/sells inside a brokerage). Not spend or income;
  Transfer activity on investment accounts (buys, sells, the brokerage side
  of a deposit) counts nowhere; cash moved into savings accounts is parked
  and counts nowhere.
- assetSale: one-time proceeds such as a house sale or the mortgage payoff
  at its closing. Excluded from spend and income; net worth shows them as
  lump sums.

Categories come only from rules. There is no per-transaction category lock:
to categorize anything, add or change a rule. categorySource is:
- rule: categoryRule set it.
- unruled: a category from before rules-only categorization; it needs a rule.
- none: uncategorized; no rule matches.
When several rules match, the most specific wins: one account over all
accounts, then exact over contains, then the longer pattern.

Rules:
- matchType "contains" matches the pattern anywhere in description or
  merchant (case-insensitive); "exact" matches the whole merchant or
  description. Use exact for short merchant names ("cvs", "amazon") that
  would otherwise match unrelated text.
- Scope a rule to one account (accountId) when the text is generic on that
  account (loan-account "recording fee", brokerage "buy").
- For a one-off, write a narrow rule (exact description, one account).
- Give every rule a note saying why it exists and any assumptions.

Workflow: POST /rules/plan with the rules you intend, read byCategoryChange
(every from → to move, with samples) to catch collateral, adjust, then POST
/rules with the same body. Both take one rule or {rules: [...],
deleteRuleIds: [...]}.

Transaction notes hold the user's context (what a check paid for). Read them
before judging a transaction. When a judgment depends on context about one
transaction, append a short note to it (PATCH /transactions/<id> {note});
keep any existing note. Reasonable assumptions belong in notes too; mark them
("assumed ...") so later readers can tell them from known facts.''';

  void mount(Router router) {
    router
      ..get('/context', _context)
      ..get('/conscious-spending', _consciousSpendingNumbers)
      ..get('/categories', _categories)
      ..get('/accounts', _accounts)
      ..get('/rules', _rules)
      ..get('/rules/<ruleId>/transactions', _ruleTransactions)
      ..get('/transactions', _transactions)
      ..get('/transactions/<transactionId>', _transaction)
      ..get('/merchants', _merchants)
      ..post('/rules/plan', _planRuleChanges);
  }

  Future<Response> _context(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final transactions = snapshot.transactions;
    return jsonOk({
      'guide': _categorizationGuide,
      'consciousSpendingAreas': [
        for (final area in ConsciousSpendingArea.values)
          {
            'id': area.name,
            'name': area.displayName,
            'ramitShareOfTakeHome': area.ramitGuideline.rangeLabel,
          },
      ],
      'counts': {
        'transactions': transactions.length,
        'uncategorized': transactions
            .where((transaction) => transaction.isUncategorized)
            .length,
        'unruled': transactions
            .where(
              (transaction) =>
                  snapshot.categorySource(transaction) == 'unruled',
            )
            .length,
        'rules': snapshot.rules.length,
      },
      'groups': [
        for (final group in snapshot.groups)
          {'id': group.id, 'name': group.name},
      ],
      'categories': snapshot.categories.map(snapshot.categoryJson).toList(),
      'accounts': snapshot.accounts.map(snapshot.accountJson).toList(),
      'endpoints': _endpointIndex,
    });
  }

  static const _endpointIndex = [
    'GET /context',
    'GET /conscious-spending',
    'POST /banks/pull {fullHistory?} (SimpleFIN pull, then re-run rules; '
        'reports new accounts and moves)',
    'PATCH /accounts/<accountId> {kind?, taxTreatment? (traditional, roth, '
        'college, taxable, excluded; null = automatic)}',
    'POST /accounts/manual {name, kind, institution?, fromHistoryAccountId?, '
        'balanceCents?, recordedOn?} (an account SimpleFIN can’t reach; '
        'fromHistoryAccountId keeps that history account’s transactions)',
    'POST /accounts/<accountId>/balance {balanceCents, recordedOn?} '
        '(manual accounts; recordedOn YYYY-MM-DD, default today)',
    'GET /projections (retirement projection: starting point, assumptions, '
        'earliest retirement age, yearly balances)',
    'PATCH /projections/assumptions {birthDate? (YYYY-MM-DD), retirementAge?, '
        'realReturnPercent?, ... } (null clears birthDate or an override)',
    'GET /categories',
    'GET /accounts',
    'GET /rules',
    'GET /rules/<ruleId>/transactions',
    'GET /transactions?category=<id|none>&source=<rule|unruled|none>'
        '&account=<id>&search=<text>&since=<yyyy-mm-dd>&until=<yyyy-mm-dd>'
        '&minAmountCents=<n>&direction=<inflow|outflow>'
        '&includeExcluded=<true|false>&limit=<n>',
    'GET /transactions/<transactionId>',
    'GET /merchants (same filters as /transactions)',
    'POST /rules/plan {pattern, categoryId, matchType?, accountId?, note?} '
        'or {rules: [...], deleteRuleIds: [...]} (dry run; ?details=true '
        'lists every moved transaction)',
    'POST /rules (same body as /rules/plan; applies it)',
    'PATCH /rules/<ruleId> {categoryId?, note?}',
    'DELETE /rules/<ruleId>',
    'POST /rules/recategorize-all (re-run every rule over every transaction)',
    'PATCH /transactions/<transactionId> {note}',
    'POST /accounts {historyKey, name, kind, institution?} (history-only '
        'account for imported history; no live balance, outside net worth)',
    'POST /transactions/import {transactions: [{accountId, postedOn, '
        'amountCents, description, externalId, note?}]} (idempotent; skips '
        'rows another source already has; re-runs rules)',
    'POST /categories {name, groupId?, consciousSpendingArea?}',
    'PATCH /categories/<categoryId> {name?, groupId?, consciousSpendingArea?}',
    'POST /categories/<categoryId>/merge {intoCategoryId}',
    'POST /groups {name}',
  ];

  /// Exactly what the Trends dashboard card shows.
  Future<Response> _consciousSpendingNumbers(Request request) async {
    // Fresh from the repositories: the Trends providers pause while their
    // tab is hidden.
    final snapshot = await CategorizationSnapshot.load(container);
    final consciousSpendingNumbers = ConsciousSpendingNumbers.endingOn(
      today: DateTime.now(),
      transactions: snapshot.transactions,
      categories: snapshot.categories,
      accounts: snapshot.accounts,
    );
    final retirementTarget = (await LiveRetirementProjection(
      container: container,
    ).load()).savingsTarget;
    final guidelineByArea = {
      for (final area in ConsciousSpendingArea.values)
        area: ConsciousSpendingGuideline.forArea(
          area,
          retirementTarget: retirementTarget,
        ),
    };
    return jsonOk({
      'lastDay': consciousSpendingNumbers.lastDay.dayKey,
      'basis':
          'Plain totals over each window, no smoothing; annualCents scales '
          'a window to one year. Take-home pay is Income on cash accounts '
          '(paychecks and RSU proceeds); investments are net money put into '
          'investments. The Investments guideline is what retiring at the '
          'planned age needs (GET /projections) once a birth year is set.',
      'guidelines': {
        for (final entry in guidelineByArea.entries)
          entry.key.name: {
            'range': entry.value.rangeLabel,
            'reason': entry.value.reason ?? 'Ramit Sethi',
          },
      },
      'windows': [
        for (final window in ConsciousSpendingWindow.values)
          _windowJson(
            consciousSpendingNumbers.totalsFor(window),
            guidelineByArea,
          ),
      ],
    });
  }

  Map<String, Object?> _windowJson(
    ConsciousSpendingWindowTotals totals,
    Map<ConsciousSpendingArea, ConsciousSpendingGuideline> guidelineByArea,
  ) {
    return {
      'window': totals.window.label,
      'firstDay': totals.firstDay.dayKey,
      'takeHomeCents': totals.takeHomeCents,
      'annualTakeHomeCents': totals.annualTakeHomeCents,
      'rows': [
        for (final area in ConsciousSpendingArea.values)
          {
            'area': area.name,
            'name': area.displayName,
            'guideline': guidelineByArea[area]!.rangeLabel,
            'percentOfTakeHome': totals.percentOfTakeHome(area),
            'offGuideline': switch (totals.percentOfTakeHome(area)) {
              null => false,
              final percent => !guidelineByArea[area]!.contains(percent),
            },
            'cents': totals.centsByArea[area],
            'annualCents': totals.annualCents(area),
          },
      ],
    };
  }

  Future<Response> _categories(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    return jsonOk({
      'categories': snapshot.categories.map(snapshot.categoryJson).toList(),
    });
  }

  Future<Response> _accounts(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    return jsonOk({
      'accounts': snapshot.accounts.map(snapshot.accountJson).toList(),
    });
  }

  Future<Response> _rules(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    return jsonOk({'rules': snapshot.rules.map(snapshot.ruleJson).toList()});
  }

  Future<Response> _ruleTransactions(Request request, String ruleId) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final rule = snapshot.rulesById[ruleId];
    if (rule == null) return jsonError('No rule $ruleId', status: 404);
    return jsonOk({
      'rule': snapshot.ruleJson(rule),
      'transactions': [
        for (final transaction in snapshot.transactions)
          if (transaction.categoryRuleId == ruleId)
            snapshot.transactionJson(transaction),
      ],
    });
  }

  Future<Response> _transactions(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final query = TransactionQuery.fromQueryParameters(
      request.url.queryParameters,
    );
    final matching = query.matchingTransactions(snapshot);
    return jsonOk({
      'total': matching.length,
      'transactions': matching
          .take(query.limit)
          .map(snapshot.transactionJson)
          .toList(),
    });
  }

  Future<Response> _transaction(Request request, String transactionId) async {
    final snapshot = await CategorizationSnapshot.load(container);
    for (final transaction in snapshot.transactions) {
      if (transaction.id == transactionId) {
        return jsonOk(snapshot.transactionJson(transaction));
      }
    }
    return jsonError('No transaction $transactionId', status: 404);
  }

  /// One row per normalized merchant: how often, how much, and how it is
  /// currently split across categories.
  Future<Response> _merchants(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final query = TransactionQuery.fromQueryParameters(
      request.url.queryParameters,
    );
    final transactionsByMerchant = <String, List<BankTransaction>>{};
    for (final transaction in query.matchingTransactions(snapshot)) {
      transactionsByMerchant
          .putIfAbsent(transaction.normalizedMerchant, () => [])
          .add(transaction);
    }
    final merchantRows =
        [
          for (final entry in transactionsByMerchant.entries)
            _merchantJson(snapshot, entry.key, entry.value),
        ]..sort(
          (left, right) =>
              (right['count'] as int).compareTo(left['count'] as int),
        );
    return jsonOk({
      'total': merchantRows.length,
      'merchants': merchantRows.take(query.limit).toList(),
    });
  }

  Map<String, Object?> _merchantJson(
    CategorizationSnapshot snapshot,
    String merchant,
    List<BankTransaction> newestFirst,
  ) {
    final countByCategoryId = <String?, int>{};
    var netCents = 0;
    for (final transaction in newestFirst) {
      netCents += transaction.amountCents;
      countByCategoryId.update(
        transaction.categoryId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return {
      'merchant': merchant,
      'count': newestFirst.length,
      'netCents': netCents,
      'firstPostedOn': newestFirst.last.postedAt.dayKey,
      'lastPostedOn': newestFirst.first.postedAt.dayKey,
      'categories': [
        for (final entry in countByCategoryId.entries)
          {
            'id': entry.key,
            'name': snapshot.categoriesById[entry.key]?.name,
            'count': entry.value,
          },
      ],
      'sampleDescriptions': {
        for (final transaction in newestFirst.take(10))
          transaction.rawDescription,
      }.take(3).toList(),
      'sampleTransactionIds': [
        for (final transaction in newestFirst.take(3)) transaction.id,
      ],
    };
  }

  /// Dry run of rule upserts/deletions: what each rule takes and every
  /// category move it causes. Nothing is written.
  Future<Response> _planRuleChanges(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final ruleChanges = RuleChangeRequest.fromBody(
      await request.readJsonObject(),
      snapshot,
    );
    final Categorizer categorizer = await container.read(
      categorizerProvider.future,
    );
    final plan = await categorizer.planRuleChanges(
      drafts: ruleChanges.drafts,
      deletedRuleIds: ruleChanges.deletedRuleIds,
    );
    return jsonOk(
      RuleChangeReport(
        plan: plan,
        snapshot: snapshot,
        includeAllTransactions:
            request.url.queryParameters['details'] == 'true',
      ).toJson(),
    );
  }
}
