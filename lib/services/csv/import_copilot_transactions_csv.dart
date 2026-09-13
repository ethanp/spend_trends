import 'package:spend_trends/domain/remove_copilot_duplicates.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/csv/copilot_csv_file.dart';
import 'package:spend_trends/services/csv/copilot_csv_link.dart';
import 'package:spend_trends/services/csv/copilot_csv_parse.dart';
import 'package:spend_trends/services/csv/copilot_csv_persist.dart';
import 'package:spend_trends/services/csv/in_progress_copilot_csv_import.dart';
import 'package:spend_trends/services/csv/copilot_import_types.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:spend_trends/util/merchant_normalize.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:uuid/uuid.dart';

export 'package:spend_trends/services/csv/copilot_import_types.dart';

const _logger = ELogger('ImportCopilotTransactionsCsv');

/// Imports a Copilot Money `transactions.csv` export.
///
/// Copilot amounts are the opposite sign of Budgets/SimpleFIN (Copilot expenses
/// are positive). Re-imports skip existing Copilot rows and linked SimpleFIN
/// matches (after belongs-to / mask linking), and can backfill empty notes.
class ImportCopilotTransactionsCsv({
  required final AccountsRepository _accountsRepository,
  required final CategoriesRepository _categoriesRepository,
  required final TransactionsRepository _transactionsRepository,
}) {
  final _uuid = const Uuid();
  late final CopilotCsvPersist _persist = CopilotCsvPersist(
    accountsRepository: _accountsRepository,
    transactionsRepository: _transactionsRepository,
    uuid: _uuid,
  );
  final _link = CopilotCsvLink();

  Future<CopilotImportResult> importLocalFile({
    void Function(CopilotImportProgress progress)? onProgress,
    CopilotImportCancellation? cancellation,
  }) async {
    final csvFile = await CopilotCsvFile.local.resolve();
    return importCsvText(
      await csvFile.readAsString(),
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  Future<CopilotImportResult> importCsvText(
    String csvText, {
    void Function(CopilotImportProgress progress)? onProgress,
    CopilotImportCancellation? cancellation,
  }) async {
    final table = CopilotCsvTable.parse(csvText);
    final session = await _beginImportSession(table.dataRowCount);
    onProgress?.call(session.progress);

    final pendingInserts = <BankTransaction>[];
    try {
      for (final row in table.dataRows) {
        await _importOneRow(
          row,
          table.columns,
          session,
          pendingInserts,
          onProgress,
          cancellation,
        );
      }
      await _persist.flushPendingWrites(session, pendingInserts);
    } on CopilotImportCancelledException {
      pendingInserts.clear();
      _markCancelled(session);
    }

    onProgress?.call(session.completedProgress);
    _logger.log(session.summaryLog);
    return session.result;
  }

  Future<void> _importOneRow(
    List<dynamic> row,
    CopilotCsvColumns columns,
    InProgressCopilotCsvImport session,
    List<BankTransaction> pendingInserts,
    void Function(CopilotImportProgress progress)? onProgress,
    CopilotImportCancellation? cancellation,
  ) async {
    _throwIfCancelled(cancellation);

    final parsed = ParsedCopilotRow.tryParse(row, columns);
    if (parsed == null) {
      await session.markInvalid(onProgress);
      return;
    }

    final accountId = await _persist.accountIdFor(parsed, session);
    _throwIfCancelled(cancellation);

    final normalizedMerchant = normalizeMerchant(parsed.name);
    final externalKey = '$accountId|${parsed.externalId}';
    final contentKey = copilotContentPresenceKey(
      accountId: accountId,
      postedAt: parsed.postedAt,
      amountCents: parsed.amountCents,
      normalizedMerchant: normalizedMerchant,
    );

    final existing =
        session.existingByExternalKey[externalKey] ??
        session.existingByContentKey[contentKey];
    if (existing != null) {
      _link.reconcileExisting(
        session: session,
        existing: existing,
        parsed: parsed,
        accountId: accountId,
        externalKey: externalKey,
        normalizedMerchant: normalizedMerchant,
      );
      await session.markAlreadyPresent(onProgress);
      return;
    }

    final matchingSimplefin = _link.matchingSimplefinCharge(
      session: session,
      accountId: accountId,
      parsed: parsed,
      normalizedMerchant: normalizedMerchant,
    );
    if (matchingSimplefin != null) {
      await session.markSimplefinMatchSkip(onProgress);
      return;
    }

    await _queueInsert(
      session: session,
      parsed: parsed,
      accountId: accountId,
      normalizedMerchant: normalizedMerchant,
      externalKey: externalKey,
      contentKey: contentKey,
      pendingInserts: pendingInserts,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  Future<void> _queueInsert({
    required InProgressCopilotCsvImport session,
    required ParsedCopilotRow parsed,
    required String accountId,
    required String normalizedMerchant,
    required String externalKey,
    required String contentKey,
    required List<BankTransaction> pendingInserts,
    required void Function(CopilotImportProgress progress)? onProgress,
    required CopilotImportCancellation? cancellation,
  }) async {
    final transaction = _persist.bankTransactionForInsert(
      parsed: parsed,
      accountId: accountId,
      session: session,
      normalizedMerchant: normalizedMerchant,
    );
    pendingInserts.add(transaction);
    session.rememberInserted(
      transaction: transaction,
      externalKey: externalKey,
      contentKey: contentKey,
    );
    await session.markImported(onProgress);
    if (pendingInserts.length < 200) return;
    _throwIfCancelled(cancellation);
    await _persist.flushInsertBatch(pendingInserts);
  }

  void _markCancelled(InProgressCopilotCsvImport session) {
    session.cancelled = true;
    _logger.log(
      'Copilot import cancelled after ${session.processedRows} rows '
      '(${session.importedTransactions} new this run).',
    );
  }

  static void _throwIfCancelled(CopilotImportCancellation? cancellation) {
    if (cancellation?.isCancelled ?? false) {
      throw CopilotImportCancelledException();
    }
  }

  Future<InProgressCopilotCsvImport> _beginImportSession(
    int dataRowCount,
  ) async {
    final accounts = await _accountsRepository.listAccounts();
    // One full scan builds external-id presence, content presence, and twins.
    final transactions = await _transactionsRepository.listAll();
    final existingByExternalKey = <String, TransactionPresence>{};
    final existingByContentKey = <String, TransactionPresence>{};
    for (final transaction in transactions) {
      final presence = _persist.presenceFor(transaction);
      existingByExternalKey['${transaction.accountId}|${transaction.externalId}'] =
          presence;
      final contentKey = copilotContentPresenceKey(
        accountId: transaction.accountId,
        postedAt: transaction.postedAt,
        amountCents: transaction.amountCents,
        normalizedMerchant: transaction.normalizedMerchant,
      );
      existingByContentKey.putIfAbsent(contentKey, () => presence);
    }

    final session = InProgressCopilotCsvImport(
      categoryIdByName: await _loadCategoryIdsByName(),
      existingByExternalKey: existingByExternalKey,
      existingByContentKey: existingByContentKey,
      matchingCharges: MatchingSimplefinCharges.from(
        accounts: accounts,
        transactions: transactions,
      ),
      dataRowCount: dataRowCount,
      importedAt: DateTime.now(),
    );
    _persist.seedAccountCache(session, accounts);
    return session;
  }

  Future<Map<String, String>> _loadCategoryIdsByName() async {
    final categories = await _categoriesRepository.listAll();
    return {
      for (final category in categories)
        category.name.trim().toLowerCase(): category.id,
    };
  }
}
