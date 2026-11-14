import 'dart:convert';

import 'package:ethan_utils/ethan_utils.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/agent_api/rule_change_request.dart';
import 'package:spend_trends/use_cases/categories/categorizer.dart';
import 'package:spend_trends/data/empower/empower_imports_folder.dart';
import 'package:spend_trends/data/empower/empower_transactions_import.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';

/// Empower history import. The app keeps every pulled export and the
/// Empower → app account mapping in its own Application Support folder
/// (`imports/empower/`), never in a repo, so a later re-import needs no
/// scratch files. See docs/empower_transactions_pull.md for getting the
/// export out of Empower.
class const AgentApiEmpowerRoutes({
  required final ProviderContainer container,
}) {
  static const _accountMappingFileName = 'account_mapping.json';
  static const transactionsExportPrefix = 'transactions_';
  static const _importsFolder = EmpowerImportsFolder();

  void mount(Router router) {
    router
      ..get('/imports/empower', _savedImports)
      ..post('/imports/empower', _importEmpowerTransactions);
  }

  /// Saved exports, newest first, and the account mapping.
  Future<Response> _savedImports(Request request) async {
    return jsonOk({
      'folder': (await _importsFolder.directory()).path,
      'exports':
          (await _importsFolder.savedExports(prefix: transactionsExportPrefix))
              .mapL(
                (file) => {
                  'file': p.basename(file.path),
                  'bytes': file.lengthSync(),
                  'savedAt': file.lastModifiedSync().toIso8601String(),
                },
              ),
      'accountMapping': {
        for (final entry in (await _accountMapping()).entries)
          '${entry.key}': entry.value.toJson(),
      },
    });
  }

  /// `{file?, accounts?, transactionTypes?, dryRun?}`.
  ///
  /// `file` is a saved `getUserTransactions` response (`~` allowed); the app
  /// copies it into its folder. Without `file`, the newest saved export is
  /// used. `accounts` maps an Empower `userAccountId` to
  /// `{accountId, label}` and is remembered once applied. `transactionTypes`
  /// defaults to contribution types. Rows match existing ones by Empower id,
  /// then by amount within 2 days: an earlier Empower import is re-keyed, a
  /// live-feed row is left alone, and only the rest are inserted.
  Future<Response> _importEmpowerTransactions(Request request) async {
    final body = await request.readJsonObject();
    final export = await _importsFolder.exportFrom(
      body['file'] as String?,
      prefix: transactionsExportPrefix,
    );
    final mappingByEmpowerAccountId = {
      ...await _accountMapping(),
      for (final entry
          in (body['accounts'] as Map<String, dynamic>? ?? const {}).entries)
        int.parse(entry.key): EmpowerAccountMapping.fromJson(
          entry.value as Map<String, dynamic>,
        ),
    };
    if (mappingByEmpowerAccountId.isEmpty) {
      throw ArgumentError('Map at least one Empower account in "accounts".');
    }
    final snapshot = await CategorizationSnapshot.load(container);
    for (final mapping in mappingByEmpowerAccountId.values) {
      if (!snapshot.accountsById.containsKey(mapping.appAccountId)) {
        throw ArgumentError('No account ${mapping.appAccountId}.');
      }
    }

    final exportJson =
        jsonDecode(export.readAsStringSync()) as Map<String, dynamic>;
    final incoming = (exportJson['spData']['transactions'] as List).mapL(
      (row) => EmpowerTransaction.fromJson(row as Map<String, dynamic>),
    );
    final importPlan =
        EmpowerTransactionsImport(
          mappingByEmpowerAccountId: mappingByEmpowerAccountId,
          transactionTypes: (body['transactionTypes'] as List?)
              ?.cast<String>()
              .toSet(),
        ).plan(
          incoming: incoming,
          existing: snapshot.transactions,
          importedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
    final report = {
      'export': p.basename(export.path),
      'exportRows': incoming.length,
      'insert': importPlan.inserts.length,
      'rekeyEarlierImport': importPlan.externalIdByAdoptedTransactionId.length,
      'alreadyImported': importPlan.alreadyImportedCount,
      'recordedByOtherSource': importPlan.recordedByOtherSource.length,
      'unmatchedEarlierImports': importPlan.unmatchedEarlierImports.length,
      'insertByAccount': _countAndCentsByAccount(importPlan.inserts, snapshot),
      'insertSample': importPlan.inserts
          .take(30)
          .mapL((transaction) => _rowJson(transaction, snapshot)),
      'unmatchedEarlierImportSample': importPlan.unmatchedEarlierImports
          .take(30)
          .mapL((transaction) => _rowJson(transaction, snapshot)),
    };
    if (body['dryRun'] == true) return jsonOk(report);

    final TransactionsRepository transactionsRepository = await container.read(
      transactionsRepositoryProvider.future,
    );
    await transactionsRepository.insertTransactions(importPlan.inserts);
    await transactionsRepository.setExternalIds(
      importPlan.externalIdByAdoptedTransactionId,
    );
    await _importsFolder.writeJson(_accountMappingFileName, {
      for (final entry in mappingByEmpowerAccountId.entries)
        '${entry.key}': entry.value.toJson(),
    });
    final Categorizer categorizer = await container.read(
      categorizerProvider.future,
    );
    final recategorized = await categorizer.recategorizeAll();
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({
      ...report,
      'recategorized': RuleChangeReport(
        plan: recategorized,
        snapshot: await CategorizationSnapshot.load(container),
      ).toJson(),
    });
  }

  static Map<String, Map<String, int>> _countAndCentsByAccount(
    List<BankTransaction> transactions,
    CategorizationSnapshot snapshot,
  ) {
    final totalsByAccount = <String, Map<String, int>>{};
    for (final transaction in transactions) {
      final String name =
          snapshot
              .accountsById[transaction.accountId]
              ?.displayNameWithInstitution ??
          transaction.accountId;
      final totals = totalsByAccount.putIfAbsent(
        name,
        () => {'count': 0, 'cents': 0},
      );
      totals['count'] = totals['count']! + 1;
      totals['cents'] = totals['cents']! + transaction.amountCents;
    }
    return totalsByAccount;
  }

  static Map<String, Object?> _rowJson(
    BankTransaction transaction,
    CategorizationSnapshot snapshot,
  ) => {
    'postedOn': transaction.postedDay.isoDate,
    'amountCents': transaction.amountCents,
    'description': transaction.rawDescription,
    'account': snapshot
        .accountsById[transaction.accountId]
        ?.displayNameWithInstitution,
  };

  static Future<Map<int, EmpowerAccountMapping>> _accountMapping() async => {
    for (final entry in (await _importsFolder.readJson(
      _accountMappingFileName,
    )).entries)
      int.parse(entry.key): EmpowerAccountMapping.fromJson(
        entry.value as Map<String, dynamic>,
      ),
  };
}
