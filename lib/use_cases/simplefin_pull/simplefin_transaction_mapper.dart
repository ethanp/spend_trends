import 'package:spend_trends/data/empower/empower_recorded_rows.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/data/simplefin/simplefin_models.dart';
import 'package:spend_trends/use_cases/simplefin_pull/simplefin_pull_progress.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';
import 'package:spend_trends/domain/transactions/merchant_normalize.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:uuid/uuid.dart';

/// Maps SimpleFIN remote transactions into local [BankTransaction] rows,
/// skipping a new row an Empower import already recorded on the account.
class SimpleFinTransactionMapper({
  required final TransactionsRepository _transactionsRepository,
  Uuid? uuid,
}) {
  final Uuid _uuid = uuid ?? const Uuid();

  Future<List<SimpleFinPulledTransaction>> upsertFromRemote({
    required SimpleFinAccount remoteAccount,
    required String localAccountId,
    required DateTime syncedAt,
  }) async {
    final newlyInserted = <SimpleFinPulledTransaction>[];
    final accountRows = await _transactionsRepository.listForAccount(
      localAccountId,
    );
    final knownExternalIds = {for (final row in accountRows) row.externalId};
    final empowerRecordedRows = EmpowerRecordedRows.forAccount(accountRows);
    for (final remoteTransaction in remoteAccount.transactions) {
      final bankTransaction = _bankTransactionFromRemote(
        remoteTransaction: remoteTransaction,
        localAccountId: localAccountId,
        syncedAt: syncedAt,
      );
      if (!knownExternalIds.contains(bankTransaction.externalId) &&
          empowerRecordedRows.claim(bankTransaction)) {
        continue;
      }
      final wasInserted = await _transactionsRepository.upsertTransaction(
        bankTransaction,
      );
      if (!wasInserted) continue;
      newlyInserted.add(
        SimpleFinPulledTransaction(
          id: bankTransaction.id,
          externalId: bankTransaction.externalId,
          description: bankTransaction.rawDescription.isEmpty
              ? bankTransaction.normalizedMerchant
              : bankTransaction.rawDescription,
          amountCents: bankTransaction.amountCents,
          postedAt: bankTransaction.postedAtMillis.dateTimeFromMillis,
          pending: bankTransaction.pending,
        ),
      );
    }
    return newlyInserted;
  }

  BankTransaction _bankTransactionFromRemote({
    required SimpleFinTransaction remoteTransaction,
    required String localAccountId,
    required DateTime syncedAt,
  }) {
    final postedSeconds = remoteTransaction.posted;
    return BankTransaction(
      id: _uuid.v4(),
      accountId: localAccountId,
      externalId: remoteTransaction.id,
      postedAtMillis: postedSeconds > 0
          ? postedSeconds * 1000
          : syncedAt.millisecondsSinceEpoch,
      amountCents: remoteTransaction.amount.asCents,
      rawDescription: remoteTransaction.description,
      normalizedMerchant: normalizeMerchant(remoteTransaction.description),
      pending: remoteTransaction.pending || postedSeconds == 0,
      importedAtMillis: syncedAt.millisecondsSinceEpoch,
    );
  }
}
