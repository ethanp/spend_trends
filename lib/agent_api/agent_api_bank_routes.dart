import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/agent_api/rule_change_request.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/domain/manual_accounts.dart';
import 'package:spend_trends/domain/pull_simplefin_transactions.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';

/// Bank pulls and account fixes, the same calls the Banks tab makes.
class const AgentApiBankRoutes({required final ProviderContainer container}) {
  void mount(Router router) {
    router
      ..post('/banks/pull', _pull)
      ..patch('/accounts/<accountId>', _updateAccount)
      ..post('/accounts/manual', _createManualAccount)
      ..post('/accounts/<accountId>/balance', _recordManualBalance);
  }

  /// `{fullHistory?: bool}`. Pulls SimpleFIN (since the last pull unless
  /// fullHistory), re-runs every rule, and reports what came in.
  Future<Response> _pull(Request request) async {
    final body = await request.readJsonObject();
    final PullSimpleFinTransactions puller = await container.read(
      pullSimpleFinTransactionsProvider.future,
    );
    final accountIdsBefore = {
      for (final account in (await CategorizationSnapshot.load(
        container,
      )).accounts)
        account.id,
    };
    final result = await puller.pull(fullHistory: body['fullHistory'] == true);
    final Categorizer categorizer = await container.read(
      categorizerProvider.future,
    );
    final recategorized = await categorizer.recategorizeAll();
    container.read(spendDataChangedProvider.notifier).notify();
    final snapshot = await CategorizationSnapshot.load(container);
    return jsonOk({
      'accountCount': result.accountCount,
      'newTransactionCount': result.transactionCount,
      'errors': [
        for (final error in result.errors)
          {'code': error.code, 'message': error.message},
      ],
      'newAccounts': [
        for (final account in snapshot.accounts)
          if (!accountIdsBefore.contains(account.id))
            snapshot.accountJson(account),
      ],
      'recategorized': RuleChangeReport(
        plan: recategorized,
        snapshot: snapshot,
      ).toJson(),
    });
  }

  /// `{kind}`, e.g. `investment` for a crypto exchange the name heuristics
  /// missed.
  Future<Response> _updateAccount(Request request, String accountId) async {
    final body = await request.readJsonObject();
    final kind = _requiredKind(body);
    final AccountsRepository accountsRepository = await container.read(
      accountsRepositoryProvider.future,
    );
    if (await accountsRepository.findById(accountId) == null) {
      return jsonError('No account $accountId', status: 404);
    }
    await accountsRepository.updateKind(accountId: accountId, kind: kind);
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({'id': accountId, 'kind': kind.name});
  }

  /// `{name, kind, institution?, fromHistoryAccountId?, balanceCents?,
  /// recordedOn?}`. With fromHistoryAccountId, that history-only account
  /// becomes manual and keeps its transactions.
  Future<Response> _createManualAccount(Request request) async {
    final body = await request.readJsonObject();
    final ManualAccounts manualAccounts = await container.read(
      manualAccountsProvider.future,
    );
    final account = await manualAccounts.create(
      name: body.requiredString('name'),
      kind: _requiredKind(body),
      institution: body['institution'] as String?,
      fromHistoryAccountId: body['fromHistoryAccountId'] as String?,
    );
    if (body['balanceCents'] case final int balanceCents) {
      await manualAccounts.recordBalance(
        account: account,
        balanceCents: balanceCents,
        recordedOn: _recordedOn(body),
      );
    }
    return _manualAccountResponse(account.id);
  }

  /// `{balanceCents, recordedOn?}` (YYYY-MM-DD, default today).
  Future<Response> _recordManualBalance(
    Request request,
    String accountId,
  ) async {
    final body = await request.readJsonObject();
    final balanceCents = body['balanceCents'];
    if (balanceCents is! int) throw ArgumentError('"balanceCents" is required.');
    final AccountsRepository accountsRepository = await container.read(
      accountsRepositoryProvider.future,
    );
    final Account? account = await accountsRepository.findById(accountId);
    if (account == null) {
      return jsonError('No account $accountId', status: 404);
    }
    final ManualAccounts manualAccounts = await container.read(
      manualAccountsProvider.future,
    );
    await manualAccounts.recordBalance(
      account: account,
      balanceCents: balanceCents,
      recordedOn: _recordedOn(body),
    );
    return _manualAccountResponse(accountId);
  }

  Future<Response> _manualAccountResponse(String accountId) async {
    container.read(spendDataChangedProvider.notifier).notify();
    final snapshot = await CategorizationSnapshot.load(container);
    final Account account = snapshot.accounts.firstWhere(
      (candidate) => candidate.id == accountId,
    );
    return jsonOk(snapshot.accountJson(account));
  }

  static AccountKind _requiredKind(Map<String, dynamic> body) {
    final kind = AccountKind.tryFromStorage(body.requiredString('kind'));
    if (kind != null) return kind;
    throw ArgumentError(
      'kind must be one of '
      '${AccountKind.values.map((kind) => kind.name).join(', ')}.',
    );
  }

  static DateTime _recordedOn(Map<String, dynamic> body) =>
      switch (body['recordedOn']) {
        final String day => DateTime.parse(day),
        _ => DateTime.now(),
      };
}
