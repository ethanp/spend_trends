import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/agent_api/rule_change_request.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:spend_trends/use_cases/categories/categorizer.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';
import 'package:spend_trends/domain/transactions/merchant_normalize.dart';
import 'package:uuid/uuid.dart';

/// History backfill from aggregator exports (Empower, …): history-only
/// accounts and idempotent transaction import. Categories still come only
/// from rules; the import re-runs them.
class const AgentApiImportRoutes({required final ProviderContainer container}) {
  /// Empower and SimpleFIN date the same contribution a day or two apart.
  static const _sameTransactionWithinDays = 3;

  void mount(Router router) {
    router
      ..post('/accounts', _upsertHistoryAccount)
      ..post('/transactions/import', _importTransactions);
  }

  /// `{historyKey, name, kind, institution?}` → a history-only account
  /// (external id `history:<historyKey>`, no live balance, outside net worth).
  /// Re-sending the same historyKey updates it.
  Future<Response> _upsertHistoryAccount(Request request) async {
    final body = await request.readJsonObject();
    final kind = AccountKind.tryFromStorage(body.requiredString('kind'));
    if (kind == null) {
      throw ArgumentError(
        'kind must be one of ${AccountKind.values.map((kind) => kind.name).join(', ')}.',
      );
    }
    final AccountsRepository accountsRepository = await container.read(
      accountsRepositoryProvider.future,
    );
    final externalId = 'history:${body.requiredString('historyKey')}';
    await accountsRepository.upsertAccount(
      Account(
        id: const Uuid().v4(),
        externalId: externalId,
        name: body.requiredString('name'),
        currency: 'USD',
        balanceCents: 0,
        status: AccountStatus.ok,
        connName: body['institution'] as String?,
        kind: kind,
      ),
    );
    final Account account = (await accountsRepository.findByExternalId(
      externalId,
    ))!;
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({'id': account.id, 'externalId': account.externalId});
  }

  /// `{transactions: [{accountId, postedOn, amountCents, description,
  /// externalId, note?}]}`. Rows already present by externalId are refreshed.
  /// A row matching a transaction another source already has on that account
  /// (same amount within a few days) is skipped; rows in one import never
  /// skip each other (an employee and employer contribution can match).
  /// Then every rule re-runs and the report shows what that moved.
  Future<Response> _importTransactions(Request request) async {
    final body = await request.readJsonObject();
    final snapshot = await CategorizationSnapshot.load(container);
    final TransactionsRepository transactionsRepository = await container.read(
      transactionsRepositoryProvider.future,
    );
    final rows = (body['transactions'] as List).mapL(
      (row) => _transactionFrom(row as Map<String, dynamic>, snapshot),
    );
    final importedExternalIds = {for (final row in rows) row.externalId};
    final otherSourceByAccountId = <String, List<BankTransaction>>{};
    final existingExternalIds = <String>{};
    for (final transaction in snapshot.transactions) {
      existingExternalIds.add(transaction.externalId);
      if (importedExternalIds.contains(transaction.externalId)) continue;
      otherSourceByAccountId
          .putIfAbsent(transaction.accountId, () => [])
          .add(transaction);
    }

    var insertedCount = 0;
    var refreshedCount = 0;
    final skippedAsDuplicates = <Map<String, Object?>>[];
    for (final incoming in rows) {
      final alreadyImported = existingExternalIds.contains(incoming.externalId);
      if (!alreadyImported &&
          _hasSameTransaction(
            otherSourceByAccountId[incoming.accountId] ?? const [],
            incoming,
          )) {
        skippedAsDuplicates.add({
          'externalId': incoming.externalId,
          'postedOn': incoming.postedDay.isoDate,
          'amountCents': incoming.amountCents,
        });
        continue;
      }
      final inserted = await transactionsRepository.upsertTransaction(incoming);
      if (inserted) {
        insertedCount++;
      } else {
        refreshedCount++;
      }
    }

    final Categorizer categorizer = await container.read(
      categorizerProvider.future,
    );
    final recategorized = await categorizer.recategorizeAll();
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({
      'inserted': insertedCount,
      'refreshed': refreshedCount,
      'skippedAsDuplicates': skippedAsDuplicates,
      'recategorized': RuleChangeReport(
        plan: recategorized,
        snapshot: await CategorizationSnapshot.load(container),
      ).toJson(),
    });
  }

  BankTransaction _transactionFrom(
    Map<String, dynamic> row,
    CategorizationSnapshot snapshot,
  ) {
    final accountId = row.requiredString('accountId');
    if (!snapshot.accountsById.containsKey(accountId)) {
      throw ArgumentError('No account $accountId.');
    }
    final amountCents = row['amountCents'];
    if (amountCents is! int) {
      throw ArgumentError('amountCents must be an integer.');
    }
    final description = row.requiredString('description');
    return BankTransaction(
      id: const Uuid().v4(),
      accountId: accountId,
      externalId: row.requiredString('externalId'),
      postedAtMillis: DateTime.parse(row.requiredString('postedOn'))
          .millisecondsSinceEpoch,
      amountCents: amountCents,
      rawDescription: description,
      normalizedMerchant: normalizeMerchant(description),
      pending: false,
      note: row['note'] as String?,
      importedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static bool _hasSameTransaction(
    List<BankTransaction> sameAccount,
    BankTransaction incoming,
  ) {
    return sameAccount.any(
      (existing) =>
          existing.amountCents == incoming.amountCents &&
          existing.postedDay.daysSince(incoming.postedDay).abs() <=
              _sameTransactionWithinDays,
    );
  }
}
