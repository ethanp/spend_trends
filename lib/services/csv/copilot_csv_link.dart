import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/csv/copilot_csv_parse.dart';
import 'package:spend_trends/services/csv/in_progress_copilot_csv_import.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

import 'copilot_csv_notes.dart';

/// Reconcile existing Copilot rows and match SimpleFIN charges.
class CopilotCsvLink() {
  BankTransaction? matchingSimplefinCharge({
    required InProgressCopilotCsvImport session,
    required String accountId,
    required ParsedCopilotRow parsed,
    required String normalizedMerchant,
  }) {
    final match = session.matchingCharges.takeMatch(
      copilotAccountId: accountId,
      postedAt: parsed.postedAt,
      amountCents: parsed.amountCents,
      normalizedMerchant: normalizedMerchant,
    );
    if (match == null) return null;
    if (!CopilotCsvNotes.isPresent(match.note)) {
      session.backfillNote(match.id, parsed.note);
    }
    return match;
  }

  void reconcileExisting({
    required InProgressCopilotCsvImport session,
    required TransactionPresence existing,
    required ParsedCopilotRow parsed,
    required String accountId,
    required String externalKey,
    required String normalizedMerchant,
  }) {
    // Snapshot before note updates — content-key hits may still carry a stale
    // TitleCase external id that needs rewriting.
    final matchedByExternal = session.existingByExternalKey.containsKey(
      externalKey,
    );

    _backfillNoteOnExisting(session, existing, parsed.note, externalKey);
    if (!matchedByExternal) {
      _queueExternalIdCanonicalize(session, existing, parsed, externalKey);
    }
    _backfillNoteOnMatchingSimplefin(
      session: session,
      accountId: accountId,
      parsed: parsed,
      normalizedMerchant: normalizedMerchant,
    );
  }

  void _backfillNoteOnExisting(
    InProgressCopilotCsvImport session,
    TransactionPresence existing,
    String? note,
    String externalKey,
  ) {
    if (existing.hasNote) return;
    session.backfillNote(existing.id, note);
    if (!CopilotCsvNotes.isPresent(note)) return;
    session.existingByExternalKey[externalKey] = TransactionPresence(
      id: existing.id,
      hasNote: true,
    );
  }

  void _queueExternalIdCanonicalize(
    InProgressCopilotCsvImport session,
    TransactionPresence existing,
    ParsedCopilotRow parsed,
    String externalKey,
  ) {
    if (existing.id.isEmpty) return;
    session.pendingExternalIdById[existing.id] = parsed.externalId;
    session.existingByExternalKey.putIfAbsent(externalKey, () => existing);
  }

  void _backfillNoteOnMatchingSimplefin({
    required InProgressCopilotCsvImport session,
    required String accountId,
    required ParsedCopilotRow parsed,
    required String normalizedMerchant,
  }) {
    final match = session.matchingCharges.findMatch(
      copilotAccountId: accountId,
      postedAt: parsed.postedAt,
      amountCents: parsed.amountCents,
      normalizedMerchant: normalizedMerchant,
      unmatchedOnly: false,
    );
    if (match == null) return;
    if (CopilotCsvNotes.isPresent(match.note)) return;
    session.backfillNote(match.id, parsed.note);
  }
}
