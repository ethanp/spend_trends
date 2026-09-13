import 'package:spend_trends/domain/month_summary.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

class const TransactionPresence({
  required final String id,
  required final bool hasNote,
});

class const _MonthFlowTotals({
  required final int outflowCents,
  required final int inflowCents,
  required final Map<String, int> spentByAccount,
});

class TransactionsRepository(final PowerSyncDatabase _powerSync) {
  Future<List<BankTransaction>> listAll({int? limit}) async {
    final sql = StringBuffer(
      'SELECT * FROM transactions ORDER BY posted_at DESC, id DESC',
    );
    if (limit != null) sql.write(' LIMIT $limit');
    final rows = await _powerSync.getAll(sql.toString());
    return rows.map(_fromRow).toList();
  }

  Future<List<BankTransaction>> listForMonth(String yearMonth) async {
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final start = DateTime(year, month, 1);
    return listPostedBetween(start, start.startOfNextMonth);
  }

  /// Inclusive of [start], inclusive of [end], by `imported_at`.
  Future<List<BankTransaction>> listImportedBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _powerSync.getAll(
      '''
      SELECT * FROM transactions
      WHERE imported_at >= ? AND imported_at <= ?
      ORDER BY posted_at DESC, id DESC
      ''',
      [
        start.toUtc().millisecondsSinceEpoch,
        end.toUtc().millisecondsSinceEpoch,
      ],
    );
    return rows.map(_fromRow).toList();
  }

  /// Inclusive of [start], exclusive of [end], by `posted_at`.
  Future<List<BankTransaction>> listPostedBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _powerSync.getAll(
      '''
      SELECT * FROM transactions
      WHERE posted_at >= ? AND posted_at < ?
      ORDER BY posted_at DESC, id DESC
      ''',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return rows.map(_fromRow).toList();
  }

  /// Rolling window ending now: `[now - days, now)`.
  Future<List<BankTransaction>> listPostedInLastDays(int days) {
    final end = DateTime.now();
    return listPostedBetween(end.subtract(Duration(days: days)), end);
  }

  Future<BankTransaction?> findByAccountExternalId({
    required String accountId,
    required String externalId,
  }) async {
    final row = await _powerSync.getOptional(
      '''
      SELECT * FROM transactions
      WHERE account_id = ? AND external_id = ?
      LIMIT 1
      ''',
      [accountId, externalId],
    );
    if (row == null) return null;
    return _fromRow(row);
  }

  /// Keys are `accountId|externalId` for O(1) resume/skip checks.
  Future<Set<String>> existingAccountExternalKeys() async {
    final presence = await presenceByAccountExternalKey();
    return presence.keys.toSet();
  }

  /// Presence map for import skip + note backfill without per-row lookups.
  Future<Map<String, TransactionPresence>>
  presenceByAccountExternalKey() async {
    final rows = await _powerSync.getAll(
      'SELECT id, account_id, external_id, note FROM transactions',
    );
    return {
      for (final row in rows)
        '${row['account_id'] as String}|${row['external_id'] as String}':
            TransactionPresence(
              id: row['id'] as String,
              hasNote: _normalizedNote(row['note'] as String?) != null,
            ),
    };
  }

  /// Inserts rows that are known not to exist yet (no pre-read).
  Future<void> insertTransactions(List<BankTransaction> transactions) async {
    if (transactions.isEmpty) return;
    await _powerSync.writeTransaction((tx) async {
      for (final transaction in transactions) {
        await tx.execute(
          '''
          INSERT INTO transactions (
            id, account_id, external_id, posted_at, amount_cents,
            raw_description, normalized_merchant, pending,
            user_category_id, suggested_category_id, note,
            transaction_type, excluded, recurring_series, imported_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            transaction.id,
            transaction.accountId,
            transaction.externalId,
            transaction.postedAt.millisecondsSinceEpoch,
            transaction.amountCents,
            transaction.rawDescription,
            transaction.normalizedMerchant,
            transaction.pending ? 1 : 0,
            transaction.userCategoryId,
            transaction.suggestedCategoryId,
            _normalizedNote(transaction.note),
            transaction.transactionType,
            transaction.excluded ? 1 : 0,
            transaction.recurringSeries,
            transaction.importedAt?.millisecondsSinceEpoch,
          ],
        );
      }
    });
  }

  Future<void> setExternalIds(
    Map<String, String> externalIdByTransactionId,
  ) async {
    if (externalIdByTransactionId.isEmpty) return;
    await _powerSync.writeTransaction((tx) async {
      for (final entry in externalIdByTransactionId.entries) {
        await tx.execute(
          'UPDATE transactions SET external_id = ? WHERE id = ?',
          [entry.value, entry.key],
        );
      }
    });
  }

  Future<bool> upsertTransaction(
    BankTransaction transaction, {
    bool overwriteUserCategory = false,
  }) async {
    final existing = await findByAccountExternalId(
      accountId: transaction.accountId,
      externalId: transaction.externalId,
    );
    final id = existing?.id ?? transaction.id;
    await _powerSync.upsert('transactions', {
      'id': id,
      'account_id': transaction.accountId,
      'external_id': transaction.externalId,
      'posted_at': transaction.postedAt.millisecondsSinceEpoch,
      'amount_cents': transaction.amountCents,
      'raw_description': transaction.rawDescription,
      'normalized_merchant': transaction.normalizedMerchant,
      'pending': transaction.pending ? 1 : 0,
      'user_category_id': overwriteUserCategory
          ? transaction.userCategoryId
          : (existing?.userCategoryId ?? transaction.userCategoryId),
      'suggested_category_id': overwriteUserCategory
          ? transaction.suggestedCategoryId
          : (existing?.suggestedCategoryId ?? transaction.suggestedCategoryId),
      // Keep an existing note when the incoming row has none (e.g. SimpleFIN sync).
      'note': _mergedNote(existing: existing?.note, incoming: transaction.note),
      'transaction_type': transaction.transactionType,
      'excluded': transaction.excluded ? 1 : 0,
      'recurring_series': transaction.recurringSeries,
      'imported_at': (existing?.importedAt ?? transaction.importedAt)
          ?.millisecondsSinceEpoch,
    });
    return existing == null;
  }

  /// Trims and stores [note]; empty/whitespace clears the note.
  Future<void> setNote({
    required String transactionId,
    required String? note,
  }) async {
    await _powerSync.execute('UPDATE transactions SET note = ? WHERE id = ?', [
      _normalizedNote(note),
      transactionId,
    ]);
  }

  /// Applies many note updates in one write transaction.
  Future<void> setNotes(Map<String, String> noteByTransactionId) async {
    if (noteByTransactionId.isEmpty) return;
    await _powerSync.writeTransaction((tx) async {
      for (final entry in noteByTransactionId.entries) {
        final normalized = _normalizedNote(entry.value);
        if (normalized == null) continue;
        await tx.execute('UPDATE transactions SET note = ? WHERE id = ?', [
          normalized,
          entry.key,
        ]);
      }
    });
  }

  static String? _mergedNote({
    required String? existing,
    required String? incoming,
  }) {
    final incomingNote = _normalizedNote(incoming);
    if (incomingNote != null) return incomingNote;
    return _normalizedNote(existing);
  }

  static String? _normalizedNote(String? note) {
    final trimmed = note?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> setUserCategory({
    required String transactionId,
    required String? categoryId,
  }) async {
    await _powerSync.execute(
      'UPDATE transactions SET user_category_id = ? WHERE id = ?',
      [categoryId, transactionId],
    );
  }

  Future<void> setSuggestedCategory({
    required String transactionId,
    required String? categoryId,
  }) async {
    await _powerSync.execute(
      '''
      UPDATE transactions
      SET suggested_category_id = ?
      WHERE id = ? AND user_category_id IS NULL
      ''',
      [categoryId, transactionId],
    );
  }

  /// Move a locked user category onto suggested so default rules can own it.
  Future<void> releaseUserCategoryToSuggested({
    required String transactionId,
    required String categoryId,
  }) async {
    await _powerSync.execute(
      '''
      UPDATE transactions
      SET user_category_id = NULL, suggested_category_id = ?
      WHERE id = ?
      ''',
      [categoryId, transactionId],
    );
  }

  Future<void> deleteTransaction(String transactionId) async {
    await _powerSync.execute('DELETE FROM transactions WHERE id = ?', [
      transactionId,
    ]);
  }

  Future<MonthSummary> monthSummary({
    required String yearMonth,
    required Map<String, String> accountNames,
    DateTime? lastSyncedAt,
  }) async {
    final transactions = await listForMonth(yearMonth);
    final flows = _aggregateMonthFlows(transactions);

    return MonthSummary(
      yearMonth: yearMonth,
      outflowCents: flows.outflowCents,
      inflowCents: flows.inflowCents,
      accountSpend: _sortedAccountSpendRows(
        spentByAccount: flows.spentByAccount,
        accountNames: accountNames,
      ),
      lastSyncedAt: lastSyncedAt,
    );
  }

  _MonthFlowTotals _aggregateMonthFlows(List<BankTransaction> transactions) {
    var outflowCents = 0;
    var inflowCents = 0;
    final spentByAccount = <String, int>{};

    for (final transaction in transactions) {
      if (transaction.excluded) continue;
      if (transaction.amountCents < 0) {
        outflowCents += -transaction.amountCents;
        spentByAccount.update(
          transaction.accountId,
          (value) => value + -transaction.amountCents,
          ifAbsent: () => -transaction.amountCents,
        );
      } else if (transaction.amountCents > 0) {
        inflowCents += transaction.amountCents;
      }
    }

    return _MonthFlowTotals(
      outflowCents: outflowCents,
      inflowCents: inflowCents,
      spentByAccount: spentByAccount,
    );
  }

  List<AccountSpendRow> _sortedAccountSpendRows({
    required Map<String, int> spentByAccount,
    required Map<String, String> accountNames,
  }) {
    return spentByAccount.entries
        .map(
          (entry) => AccountSpendRow(
            accountId: entry.key,
            accountName: accountNames[entry.key] ?? 'Account',
            spentCents: entry.value,
          ),
        )
        .toList()
      ..sort((left, right) => right.spentCents.compareTo(left.spentCents));
  }

  static BankTransaction _fromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    return BankTransaction(
      id: columns['id'] as String,
      accountId: columns['account_id'] as String,
      externalId: columns['external_id'] as String,
      postedAt: columns['posted_at'].asInt().dateTimeFromMillis,
      amountCents: columns['amount_cents'].asInt(),
      rawDescription: columns['raw_description'] as String,
      normalizedMerchant: columns['normalized_merchant'] as String,
      pending: columns['pending'].asInt() == 1,
      userCategoryId: columns['user_category_id'] as String?,
      suggestedCategoryId: columns['suggested_category_id'] as String?,
      note: columns['note'] as String?,
      transactionType: columns['transaction_type'] as String?,
      excluded: columns['excluded'] != null && columns['excluded'].asInt() == 1,
      recurringSeries: columns['recurring_series'] as String?,
      importedAt: columns['imported_at'].asIntOrNull().dateTimeFromMillis,
    );
  }
}

final transactionsRepositoryProvider = FutureProvider<TransactionsRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return TransactionsRepository(database);
});
