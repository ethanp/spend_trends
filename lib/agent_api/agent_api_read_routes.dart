import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/agent_api/live_retirement_projection.dart';
import 'package:spend_trends/agent_api/rule_change_request.dart';
import 'package:spend_trends/agent_api/transaction_query.dart';
import 'package:spend_trends/use_cases/categories/categorizer.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/categories/conscious_spending_numbers.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/data/repositories/account_balance_snapshots_repository.dart';
import 'package:spend_trends/data/repositories/life_events_repository.dart';

/// Read-only audit routes: overview, categories, accounts, rules,
/// transactions, per-merchant rollups, and rule dry runs.
class const AgentApiReadRoutes({required final ProviderContainer container}) {
  static const _categorizationGuide = '''
Spend Trends tracks categorized bank activity for one person who budgets with
Ramit Sethi's Conscious Spending Plan toward a FIRE timeline.

Category roles:
- spend: real consumption. Each spend category belongs to one conscious
  spending area (fixedCosts, guiltFree) measured as a share of pay: take-home
  plus payroll contributions. The user has no savings-goals bucket: planned
  expenses come straight from paychecks, so the plan is three numbers
  (fixedCosts, investments, guiltFree).
- income (Income): take-home pay. Paychecks, plus RSU sale proceeds once
  they reach a cash account ("Funds Transfer From Brokerage"); RSUs are
  compensation. Income on investment accounts (dividends, sales still in the
  brokerage) is a return, not take-home pay.
- investments (Investments): net money put into investments. On cash
  accounts, deposits to a brokerage/crypto add and money back from it
  subtracts (a margin draw is money back, its paydown a deposit); on
  investment accounts, 401(k)/HSA payroll contributions add, and also count
  as pay, since the paycheck never showed them.
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
- matchType "contains" matches the pattern anywhere in description,
  merchant, or the transaction's note (case-insensitive); "exact" matches
  the whole merchant or description. Use exact for short merchant names ("cvs", "amazon") that
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
("assumed ...") so later readers can tell them from known facts.

Notes are also how one transaction gets a category its bank text cannot:
contains rules match notes, and setting a note re-runs the rules on that
transaction. When bank text is generic ("Deposit Mobile Banking", a check
number, "Outgoing Wire", a Zelle), label the transaction instead of ruling on
the bank text: append a note that names what it is in the proper term
("homeowner's insurance premium refund", "title company closing wire") plus
what it is assumed or known from, then add a contains rule on that label
phrase. Do not key a rule on the user's loose wording or on a generic word
scoped to an account to make it win. A label longer than the generic rule's
pattern outranks it; scope the label rule to an account only when the
generic rule it must beat is itself scoped or exact.

Lifestyle costs are Fixed costs plus Guilt-free: the spending the FIRE
number rests on. A rule with "excludesFromLifestyleCosts": true leaves what
it categorizes out of them (a closing, the old home's mortgage and utilities
while two homes overlap). Furnishing a home or medical costs are lifestyle
costs, not excluded. The transaction keeps the rule's category, so category
trends still show it, but it fills no conscious spending area and stays out
of the projection's spending baseline. To exclude a few transactions whose
bank text also matches ordinary ones, note them with a phrase and add an
excluding rule on that phrase in the same category. PATCH /rules/<id>
{excludesFromLifestyleCosts} changes an existing rule.

Margin loans against a brokerage stay in Investments on the cash side: the
draw into checking subtracts (equity pulled out), the paydown adds (equity
restored), and the pair nets to the interest.''';

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
      'consciousSpendingAreas': ConsciousSpendingArea.values.mapL(
        (area) => {
          'id': area.name,
          'name': area.displayName,
          'ramitShareOfTakeHome': area.ramitGuideline.targetLabel,
        },
      ),
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
      'groups': snapshot.groups.mapL(
        (group) => {'id': group.id, 'name': group.name},
      ),
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
    'GET /life-events (jobs, homes, children the projection plans with; '
        'each with its kind’s details)',
    'POST /life-events {id?, kind: milestone|job|home|childBirth, title, '
        'startedOn, endedOn?, note?, details?} (creates, or replaces by id; '
        'a future home event is a planned move)',
    'DELETE /life-events/<eventId>',
    'GET /owned-assets (homes and other assets, sale dates, valuations)',
    'POST /owned-assets/<assetId>/valuations {valueCents, valuedOn}',
    'PATCH /owned-assets/<assetId>/valuations/<valuationId> {valueCents?, '
        'valuedOn?} (a home counts as 0 from its sale date)',
    'GET /projections (retirement projection: starting point, assumptions, '
        'earliest retirement age, yearly balances)',
    'PATCH /projections/assumptions {birthDate? (YYYY-MM-DD), retirementAge?, '
        'realReturnPercent?, ..., assumedMoveYear?, assumedMovePrice?, '
        'assumedMoveDownPayment?, assumedMoveMortgageRatePercent?} (null '
        'clears birthDate, an override, or the assumed move; an assumed move '
        'is a 30-year-fixed home the projection adds without a life event)',
    'GET /categories',
    'GET /accounts',
    'GET /rules?search=<pattern or note text>&category=<id>'
        '&excludesFromLifestyleCosts=<true|false>',
    'GET /rules/<ruleId>/transactions',
    'GET /transactions?ids=&category=<ids|none>&area=<fixedCosts,investments,'
        'guiltFree,none>&source=<rule|unruled|none>&account=<ids>'
        '&accountKind=<checking,savings,creditCard,investment,loans,...>'
        '&rule=<id>&search=<text>&note=<text>&hasNote=<bool>'
        '&excludedFromLifestyleCosts=<bool>&since=<yyyy-mm-dd>'
        '&until=<yyyy-mm-dd>&importedSince=<iso datetime>'
        '&minAmountCents=<n>&maxAmountCents=<n>'
        '&direction=<inflow|outflow>&includeExcluded=<bool>&limit=<n> '
        '(list parameters are comma-separated)',
    'GET /transactions/totals?groupBy=<category|area|merchant|account|'
        'accountKind|month|rule> plus any /transactions filter (count, sum, '
        'outflow, inflow per group)',
    'POST /transactions/notes {ids? | query?: {<any /transactions filter>}, '
        'note, mode?: append|replace, dryRun?} (notes many rows, then re-runs '
        'the rules on them once; pair with a contains rule on the note phrase)',
    'POST /transactions/remove {ids, apply?} (previews unless apply is true; '
        'ids only)',
    'GET /cash-flow?since=&until= (pay, areas, excluded from lifestyle '
        'costs, spending with no area, transfers in and out of cash by '
        'merchant, cash balance change)',
    'GET /accounts/<accountId>/balances?since=&until=&every=<month|day>',
    'GET /duplicates (Copilot rows the live feed recorded again, and '
        'same-account repeats; nothing deleted)',
    'POST /duplicates/remove {linked?, sameAccount?} (deletes what GET '
        '/duplicates lists; set a kind false to keep it)',
    'GET /transactions/<transactionId>',
    'GET /merchants (same filters as /transactions)',
    'POST /rules/plan {pattern, categoryId, matchType?, accountId?, note?, '
        'excludesFromLifestyleCosts?} '
        'or {rules: [...], deleteRuleIds: [...]} (dry run; ?details=true '
        'lists every moved transaction)',
    'POST /rules (same body as /rules/plan; applies it)',
    'PATCH /rules/<ruleId> {categoryId?, note?, excludesFromLifestyleCosts?}',
    'DELETE /rules/<ruleId>',
    'POST /rules/recategorize-all (re-run every rule over every transaction)',
    'PATCH /transactions/<transactionId> {note}',
    'POST /accounts {historyKey, name, kind, institution?} (history-only '
        'account for imported history; no live balance, outside net worth)',
    'GET /imports/empower (saved Empower exports and the account mapping, '
        'kept in the app’s Application Support folder)',
    'POST /imports/empower {file?, accounts?: {<empowerUserAccountId>: '
        '{accountId, label}}, transactionTypes?, dryRun?} (copies the export '
        'into the app’s folder, re-keys earlier Empower imports, skips rows '
        'the live feed has, inserts the rest; see '
        'docs/empower_transactions_pull.md)',
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
    final AccountBalanceSnapshotsRepository balanceSnapshotsRepository =
        await container.read(accountBalanceSnapshotsRepositoryProvider.future);
    final LifeEventsRepository lifeEventsRepository = await container.read(
      lifeEventsRepositoryProvider.future,
    );
    final consciousSpendingNumbers = ConsciousSpendingNumbers.endingOn(
      today: DateTime.now(),
      transactions: snapshot.transactions,
      categories: snapshot.categories,
      accounts: snapshot.accounts,
      balanceSnapshots: await balanceSnapshotsRepository.listAll(),
      lifeEvents: await lifeEventsRepository.listNewestFirst(),
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
          'a window to one year. Each area is a share of pay: take-home '
          '(Income on cash accounts: paychecks and RSU proceeds) plus '
          'payroll contributions (Investments on investment accounts: '
          '401(k), HSA). Investments are net money put into investments '
          'plus mortgage principal (home equity); mortgagePrincipal is that '
          'part. Principal is measured from drops in loan-account balance '
          'snapshots (an asset-sale payoff is not principal from pay) and '
          'amortized from the home life event before its loan has snapshots. '
          'It moves out of fixedCosts (Housing); interest, escrow, and '
          'mortgage insurance stay there. Principal on a home already moved '
          'out of (a home overlap) moves out of excludedFromLifestyleCosts '
          'instead, so savings is unchanged. '
          'The Investments guideline is what retiring at the planned age '
          'needs (GET /projections) once a birth year is set; it counts the '
          'projected mortgage principal as investing too. '
          'excludedFromLifestyleCosts is spending whose rule leaves it out '
          'of lifestyle costs (Fixed costs plus Guilt-free): it keeps its '
          'category but fills no area and is left out of the projection '
          'baseline. savings is pay left after the areas and '
          'excludedFromLifestyleCosts, negative when cash was drawn down; '
          'its target is 0% in either direction.',
      'guidelines': {
        for (final entry in guidelineByArea.entries)
          entry.key.name: {
            'target': entry.value.targetLabel,
            'reason': entry.value.reason ?? 'Ramit Sethi',
          },
      },
      'windows': ConsciousSpendingWindow.values.mapL(
        (window) => _windowJson(
          consciousSpendingNumbers.totalsFor(window),
          guidelineByArea,
        ),
      ),
    });
  }

  Map<String, Object?> _windowJson(
    ConsciousSpendingWindowTotals totals,
    Map<ConsciousSpendingArea, ConsciousSpendingGuideline> guidelineByArea,
  ) {
    return {
      'window': totals.window.label,
      'firstDay': totals.firstDay.dayKey,
      'payCents': totals.payCents,
      'takeHomeCents': totals.takeHomeCents,
      'payrollContributionCents': totals.payrollContributionCents,
      'annualPayCents': totals.annualPayCents,
      'rows': ConsciousSpendingArea.values.mapL(
        (area) => {
          'area': area.name,
          'name': area.displayName,
          'guideline': guidelineByArea[area]!.targetLabel,
          'percentOfPay': totals.percentOfPay(area),
          'offGuideline': switch (totals.percentOfPay(area)) {
            null => false,
            final percent => !guidelineByArea[area]!.isMetBy(percent),
          },
          'cents': totals.centsByArea[area],
          'annualCents': totals.annualCents(area),
          'targetAnnualCents': guidelineByArea[area]!.impliedCents(
            totals.annualPayCents,
          ),
        },
      ),
      'mortgagePrincipal': {
        'cents': totals.mortgagePrincipalCents,
        'annualCents': totals.annualMortgagePrincipalCents,
      },
      'excludedFromLifestyleCosts': {
        'percentOfPay': totals.excludedFromLifestylePercentOfPay,
        'cents': totals.excludedFromLifestyleCents,
        'annualCents': totals.annualExcludedFromLifestyleCents,
      },
      'savings': {
        'guideline': ConsciousSpendingGuideline.savings.targetLabel,
        'percentOfPay': totals.savingsPercentOfPay,
        'cents': totals.savingsCents,
        'annualCents': totals.annualSavingsCents,
      },
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

  /// `?search=` (pattern or note substring), `?category=<id>`,
  /// `?excludesFromLifestyleCosts=true|false`.
  Future<Response> _rules(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final parameters = request.url.queryParameters;
    final String? search = parameters['search']?.trim().toLowerCase();
    final String? categoryId = parameters['category'];
    final String? excludes = parameters['excludesFromLifestyleCosts'];
    return jsonOk({
      'rules': [
        for (final rule in snapshot.rules)
          if ((search == null ||
                  rule.pattern.contains(search) ||
                  (rule.note?.toLowerCase().contains(search) ?? false)) &&
              (categoryId == null || rule.categoryId == categoryId) &&
              (excludes == null ||
                  rule.excludesFromLifestyleCosts == (excludes == 'true')))
            snapshot.ruleJson(rule),
      ],
    });
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
        transactionsByMerchant.entries.mapL(
          (entry) => _merchantJson(snapshot, entry.key, entry.value),
        )..sort(
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
      'firstPostedOn': newestFirst.last.postedDay.isoDate,
      'lastPostedOn': newestFirst.first.postedDay.isoDate,
      'categories': countByCategoryId.entries.mapL(
        (entry) => {
          'id': entry.key,
          'name': snapshot.categoriesById[entry.key]?.name,
          'count': entry.value,
        },
      ),
      'sampleDescriptions': {
        for (final transaction in newestFirst.take(10))
          transaction.rawDescription,
      }.take(3).toList(),
      'sampleTransactionIds': newestFirst
          .take(3)
          .mapL((transaction) => transaction.id),
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
