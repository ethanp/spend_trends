import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/csv/copilot_category_map.dart';
import 'package:spend_trends/services/csv/copilot_csv_parse.dart';
import 'package:spend_trends/services/csv/in_progress_copilot_csv_import.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:uuid/uuid.dart';

import 'copilot_csv_notes.dart';

/// Flush pending inserts/notes/external-ids and ensure Copilot accounts exist.
class CopilotCsvPersist({
  required final AccountsRepository accountsRepository,
  required final TransactionsRepository transactionsRepository,
  required final Uuid uuid,
}) {
  Future<void> flushPendingWrites(
    InProgressCopilotCsvImport session,
    List<BankTransaction> pendingInserts,
  ) async {
    await flushInsertBatch(pendingInserts);
    await flushPendingNotes(session);
    await flushPendingExternalIds(session);
  }

  Future<void> flushInsertBatch(List<BankTransaction> pendingInserts) async {
    if (pendingInserts.isEmpty) return;
    await transactionsRepository.insertTransactions(pendingInserts);
    pendingInserts.clear();
  }

  Future<void> flushPendingNotes(InProgressCopilotCsvImport session) async {
    if (session.pendingNoteById.isEmpty) return;
    await transactionsRepository.setNotes(session.pendingNoteById);
    session.notesFilledCount = session.pendingNoteById.length;
    session.pendingNoteById.clear();
  }

  Future<void> flushPendingExternalIds(
    InProgressCopilotCsvImport session,
  ) async {
    if (session.pendingExternalIdById.isEmpty) return;
    session.externalIdsCanonicalized = session.pendingExternalIdById.length;
    await transactionsRepository.setExternalIds(session.pendingExternalIdById);
    session.pendingExternalIdById.clear();
  }

  void seedAccountCache(
    InProgressCopilotCsvImport session,
    List<Account> accounts,
  ) {
    for (final account in accounts) {
      if (!account.isCopilot) continue;
      final parts = account.externalId.split(':');
      if (parts.length < 3) continue;
      final accountMask = parts.last;
      final accountName = parts.sublist(1, parts.length - 1).join(':');
      session.accountIdByKey['$accountName|$accountMask'] = account.id;
    }
  }

  Future<String> accountIdFor(
    ParsedCopilotRow parsed,
    InProgressCopilotCsvImport session,
  ) async {
    final cachedId = session.accountIdByKey[parsed.accountKey];
    if (cachedId != null) return cachedId;

    final accountId = await ensureAccount(
      accountName: parsed.accountName.isEmpty ? 'Copilot' : parsed.accountName,
      accountMask: parsed.accountMask,
    );
    session.accountIdByKey[parsed.accountKey] = accountId;
    session.matchingCharges.registerAccounts(
      await accountsRepository.listAccounts(),
    );
    return accountId;
  }

  BankTransaction bankTransactionForInsert({
    required ParsedCopilotRow parsed,
    required String accountId,
    required InProgressCopilotCsvImport session,
    required String normalizedMerchant,
  }) {
    final specialFromType = SpecialCategory.fromTransactionType(
      parsed.transactionType,
    );
    final budgetsCategoryName = specialFromType != null
        ? null
        : spendCategoryNameForCopilot(parsed.categoryText);
    final mappedCategoryId = budgetsCategoryName == null
        ? null
        : session.categoryIdByName[budgetsCategoryName.toLowerCase()];
    final defaultCategoryId = specialFromType?.id ?? mappedCategoryId;
    return BankTransaction(
      id: uuid.v4(),
      accountId: accountId,
      externalId: parsed.externalId,
      postedAt: parsed.postedAt,
      amountCents: parsed.amountCents,
      rawDescription: parsed.name,
      normalizedMerchant: normalizedMerchant,
      pending: parsed.pending,
      userCategoryId: null,
      suggestedCategoryId: defaultCategoryId,
      note: parsed.note,
      transactionType: parsed.transactionType,
      excluded: parsed.excluded,
      recurringSeries: parsed.recurringSeries,
      importedAt: session.importedAt,
    );
  }

  Future<String> ensureAccount({
    required String accountName,
    required String accountMask,
  }) async {
    final externalId = 'copilot:$accountName:$accountMask';
    final existing = await accountsRepository.findByExternalId(externalId);
    if (existing != null) return existing.id;

    final accountId = uuid.v4();
    final draft = Account(
      id: accountId,
      externalId: externalId,
      name: accountMask.isEmpty ? accountName : '$accountName ·$accountMask',
      currency: 'USD',
      balanceCents: 0,
      lastSyncedAt: DateTime.now(),
      status: AccountStatus.ok,
      statusMessage: 'Imported from Copilot CSV',
    );
    await accountsRepository.upsertAccount(
      draft.copyWith(kind: AccountKindClassifier.classify(draft)),
    );
    return accountId;
  }

  TransactionPresence presenceFor(BankTransaction transaction) {
    return TransactionPresence(
      id: transaction.id,
      hasNote: CopilotCsvNotes.isPresent(transaction.note),
    );
  }
}
