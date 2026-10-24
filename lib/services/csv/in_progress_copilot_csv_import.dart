import 'package:spend_trends/domain/remove_copilot_duplicates.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/csv/copilot_import_types.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:ethan_utils/ethan_utils.dart';

const _logger = ELogger('InProgressCopilotCsvImport');

/// In-memory state for one Copilot CSV import run.
class InProgressCopilotCsvImport({
  required final Map<String, TransactionPresence> existingByExternalKey,
  required final Map<String, TransactionPresence> existingByContentKey,
  required final MatchingSimplefinCharges matchingCharges,
  required final int dataRowCount,
  required final DateTime importedAt,
}) {
  final Map<String, String> accountIdByKey = {};
  final Map<String, String> pendingNoteById = {};
  final Map<String, String> pendingExternalIdById = {};
  var processedRows = 0;
  var importedTransactions = 0;
  var skippedRows = 0;
  var alreadyPresentCount = 0;
  var simplefinMatchSkipCount = 0;
  var notesFilledCount = 0;
  var externalIdsCanonicalized = 0;
  var cancelled = false;

  CopilotImportProgress get progress =>
      CopilotImportProgress(completed: processedRows, total: dataRowCount);

  CopilotImportProgress get completedProgress => CopilotImportProgress(
    completed: cancelled ? processedRows : dataRowCount,
    total: dataRowCount,
  );

  CopilotImportResult get result => CopilotImportResult(
    transactionCount: importedTransactions,
    accountCount: accountIdByKey.length,
    skippedRows: skippedRows,
    alreadyPresentCount: alreadyPresentCount,
    notesFilledCount: notesFilledCount,
    simplefinMatchSkipCount: simplefinMatchSkipCount,
    cancelled: cancelled,
  );

  String get summaryLog =>
      '${cancelled ? 'Copilot import cancelled' : 'Copilot import done'}: '
      '$importedTransactions new, '
      '$alreadyPresentCount already present, '
      '$simplefinMatchSkipCount SimpleFIN matches, '
      '$notesFilledCount notes filled, '
      '$externalIdsCanonicalized external ids canonicalized, '
      '${accountIdByKey.length} accounts, $skippedRows invalid';

  /// Queues a note only when [transactionId] currently has none in the batch.
  void backfillNote(String transactionId, String? note) {
    final trimmed = note?.trim() ?? '';
    if (trimmed.isEmpty || transactionId.isEmpty) return;
    pendingNoteById.putIfAbsent(transactionId, () => trimmed);
  }

  void rememberInserted({
    required BankTransaction transaction,
    required String externalKey,
    required String contentKey,
  }) {
    final presence = TransactionPresence(
      id: transaction.id,
      hasNote: (transaction.note?.trim() ?? '').isNotEmpty,
    );
    existingByExternalKey[externalKey] = presence;
    existingByContentKey[contentKey] = presence;
  }

  Future<void> markInvalid(
    void Function(CopilotImportProgress progress)? onProgress,
  ) async {
    skippedRows += 1;
    await _advance(onProgress);
  }

  Future<void> markAlreadyPresent(
    void Function(CopilotImportProgress progress)? onProgress,
  ) async {
    alreadyPresentCount += 1;
    await _advance(onProgress);
  }

  Future<void> markSimplefinMatchSkip(
    void Function(CopilotImportProgress progress)? onProgress,
  ) async {
    simplefinMatchSkipCount += 1;
    await _advance(onProgress);
  }

  Future<void> markImported(
    void Function(CopilotImportProgress progress)? onProgress,
  ) async {
    importedTransactions += 1;
    await _advance(onProgress);
    if (importedTransactions % 1000 == 0) {
      _logger.log('Imported $importedTransactions Copilot rows…');
    }
  }

  Future<void> _advance(
    void Function(CopilotImportProgress progress)? onProgress,
  ) async {
    processedRows += 1;
    if (onProgress == null) return;
    if (processedRows != dataRowCount && processedRows % 500 != 0) return;
    onProgress(progress);
    await Future<void>.delayed(Duration.zero);
  }
}

/// account|day|amount|merchantFingerprint — survives external-id casing changes.
String copilotContentPresenceKey({
  required String accountId,
  required DateTime postedAt,
  required int amountCents,
  required String normalizedMerchant,
}) {
  return '$accountId|${postedAt.dayKey}|$amountCents|'
      '${merchantFingerprint(normalizedMerchant)}';
}
