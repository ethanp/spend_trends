import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/agent_api/rule_change_request.dart';
import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/domain/empower_transactions_import.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

/// Empower history import. The app keeps every pulled export and the
/// Empower → app account mapping in its own Application Support folder
/// (`imports/empower/`), never in a repo, so a later re-import needs no
/// scratch files. See docs/empower_transactions_pull.md for getting the
/// export out of Empower.
class const AgentApiEmpowerRoutes({
  required final ProviderContainer container,
}) {
  static const _accountMappingFileName = 'account_mapping.json';
  static const _exportFilePrefix = 'transactions_';

  void mount(Router router) {
    router
      ..get('/imports/empower', _savedImports)
      ..post('/imports/empower', _importEmpowerTransactions);
  }

  Future<Directory> _importsDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'imports', 'empower'))
      ..createSync(recursive: true);
  }

  /// Saved exports, newest first, and the account mapping.
  Future<Response> _savedImports(Request request) async {
    final directory = await _importsDirectory();
    return jsonOk({
      'folder': directory.path,
      'exports': [
        for (final file in _savedExports(directory))
          {
            'file': p.basename(file.path),
            'bytes': file.lengthSync(),
            'savedAt': file.lastModifiedSync().toIso8601String(),
          },
      ],
      'accountMapping': {
        for (final entry in (await _accountMapping(directory)).entries)
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
    final directory = await _importsDirectory();
    final File export = body['file'] == null
        ? (_savedExports(directory).firstOrNull ??
              (throw ArgumentError('No saved export; pass "file".')))
        : _saveExport(body['file'] as String, directory);
    final mappingByEmpowerAccountId = {
      ...await _accountMapping(directory),
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
    final incoming = [
      for (final row in (exportJson['spData']['transactions'] as List))
        EmpowerTransaction.fromJson(row as Map<String, dynamic>),
    ];
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
      'insertSample': [
        for (final transaction in importPlan.inserts.take(30))
          _rowJson(transaction, snapshot),
      ],
      'unmatchedEarlierImportSample': [
        for (final transaction in importPlan.unmatchedEarlierImports.take(30))
          _rowJson(transaction, snapshot),
      ],
    };
    if (body['dryRun'] == true) return jsonOk(report);

    final TransactionsRepository transactionsRepository = await container.read(
      transactionsRepositoryProvider.future,
    );
    await transactionsRepository.insertTransactions(importPlan.inserts);
    await transactionsRepository.setExternalIds(
      importPlan.externalIdByAdoptedTransactionId,
    );
    _saveAccountMapping(directory, mappingByEmpowerAccountId);
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

  /// Copies [sourcePath] into [directory] under a timestamped name.
  static File _saveExport(String sourcePath, Directory directory) {
    final String home = Platform.environment['HOME'] ?? '';
    final source = File(sourcePath.replaceFirst(RegExp(r'^~'), home));
    if (!source.existsSync()) throw ArgumentError('No file at $sourcePath.');
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .split('.')
        .first;
    return source.copySync(
      p.join(directory.path, '$_exportFilePrefix$stamp.json'),
    );
  }

  static List<File> _savedExports(Directory directory) => [
    for (final entity in directory.listSync())
      if (entity is File &&
          p.basename(entity.path).startsWith(_exportFilePrefix))
        entity,
  ]..sort((left, right) => right.path.compareTo(left.path));

  static Future<Map<int, EmpowerAccountMapping>> _accountMapping(
    Directory directory,
  ) async {
    final file = File(p.join(directory.path, _accountMappingFileName));
    if (!file.existsSync()) return {};
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return {
      for (final entry in json.entries)
        int.parse(entry.key): EmpowerAccountMapping.fromJson(
          entry.value as Map<String, dynamic>,
        ),
    };
  }

  static void _saveAccountMapping(
    Directory directory,
    Map<int, EmpowerAccountMapping> mappingByEmpowerAccountId,
  ) {
    File(p.join(directory.path, _accountMappingFileName)).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        for (final entry in mappingByEmpowerAccountId.entries)
          '${entry.key}': entry.value.toJson(),
      }),
    );
  }
}
