import 'dart:convert';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_empower_routes.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/data/empower/empower_imports_folder.dart';
import 'package:spend_trends/data/empower/empower_tax_basis_import.dart';
import 'package:spend_trends/data/empower/empower_transactions_import.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';
import 'package:spend_trends/domain/accounts/account.dart';

/// Tax basis from Empower holdings: what each investment account cost, so
/// the projection taxes only real gains and knows what a Roth gives back
/// tax-free. See docs/empower_transactions_pull.md for the pull.
class const AgentApiEmpowerTaxBasisRoutes({
  required final ProviderContainer container,
}) {
  static const _holdingsExportPrefix = 'holdings_';
  static const _holdingsAccountMappingFileName =
      'holdings_account_mapping.json';
  static const _importsFolder = EmpowerImportsFolder();

  void mount(Router router) {
    router.post('/imports/empower/tax-basis', _importTaxBasis);
  }

  /// `{file?, accounts?, dryRun?}`.
  ///
  /// `file` is a saved `invest/getHoldings` response (`~` allowed), copied
  /// into the app's folder; without it the newest saved one is used.
  /// `accounts` maps an Empower `userAccountId` to an app account id and is
  /// remembered once applied. A Roth's basis subtracts the reinvested
  /// dividends in the newest saved transactions export. An account with a
  /// holding that has no cost is reported and left alone.
  Future<Response> _importTaxBasis(Request request) async {
    final body = await request.readJsonObject();
    final export = await _importsFolder.exportFrom(
      body['file'] as String?,
      prefix: _holdingsExportPrefix,
    );
    final appAccountIdByEmpowerAccountId = {
      ...await _importsFolder.readJson(_holdingsAccountMappingFileName),
      ...body['accounts'] as Map<String, dynamic>? ?? const {},
    };
    if (appAccountIdByEmpowerAccountId.isEmpty) {
      throw ArgumentError('Map at least one Empower account in "accounts".');
    }
    final snapshot = await CategorizationSnapshot.load(container);
    final accountByEmpowerAccountId = <int, Account>{
      for (final entry in appAccountIdByEmpowerAccountId.entries)
        int.parse(entry.key):
            snapshot.accountsById[entry.value as String] ??
            (throw ArgumentError('No account ${entry.value}.')),
    };
    final accountBases = EmpowerAccountTaxBasis.forMappedAccounts(
      accountByEmpowerAccountId: accountByEmpowerAccountId,
      holdings: _holdingsIn(jsonDecode(export.readAsStringSync())),
      transactions: await _newestTransactionsExport(),
    );
    final report = {
      'export': p.basename(export.path),
      'accounts': accountBases.mapL(_accountBasisJson),
    };
    if (body['dryRun'] == true) return jsonOk(report);

    final AccountsRepository accountsRepository = await container.read(
      accountsRepositoryProvider.future,
    );
    for (final accountBasis in accountBases) {
      final int? basisCents = accountBasis.taxBasisCents;
      if (basisCents == null) continue;
      await accountsRepository.updateTaxBasis(
        accountId: accountBasis.account.id,
        taxBasis: TaxBasis(cents: basisCents, asOf: export.lastModifiedSync()),
      );
    }
    await _importsFolder.writeJson(
      _holdingsAccountMappingFileName,
      appAccountIdByEmpowerAccountId,
    );
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk(report);
  }

  static List<EmpowerHolding> _holdingsIn(Object? response) {
    final holdings = switch (response) {
      {'spData': {'holdings': final List<dynamic> rows}} => rows,
      {'holdings': final List<dynamic> rows} => rows,
      _ => throw const FormatException('No holdings in the export.'),
    };
    return holdings.mapL(
      (row) => EmpowerHolding.fromJson(row as Map<String, dynamic>),
    );
  }

  static Future<List<EmpowerTransaction>> _newestTransactionsExport() async {
    final exports = await _importsFolder.savedExports(
      prefix: AgentApiEmpowerRoutes.transactionsExportPrefix,
    );
    if (exports.isEmpty) return const [];
    final json =
        jsonDecode(exports.first.readAsStringSync()) as Map<String, dynamic>;
    return (json['spData']['transactions'] as List).mapL(
      (row) => EmpowerTransaction.fromJson(row as Map<String, dynamic>),
    );
  }

  static Map<String, Object?> _accountBasisJson(
    EmpowerAccountTaxBasis accountBasis,
  ) => {
    'empowerAccountId': accountBasis.empowerAccountId,
    'account': accountBasis.account.displayNameWithInstitution,
    'appBalanceCents': accountBasis.account.balanceCents,
    'holdingsValueCents': accountBasis.holdingsValueCents,
    'holdingsCostCents': accountBasis.holdingsCostCents,
    if (accountBasis.isRoth)
      'reinvestedDividendsCents': accountBasis.reinvestedDividendsCents,
    'taxBasisCents': accountBasis.taxBasisCents,
    'holdingsWithoutCost': accountBasis.holdingsWithoutCost.mapL(
      (holding) => holding.ticker,
    ),
  };
}
