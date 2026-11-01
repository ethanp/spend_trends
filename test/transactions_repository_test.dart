import 'package:spend_trends/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Documents the upsert contract used by [TransactionsRepository]: when the
/// same (account_id, external_id) is written twice, the first local id wins
/// and later fields (e.g. pending → posted) overwrite.
void main() {
  test('pending then posted prefers stable local id', () {
    const accountId = 'acc-1';
    const externalId = 'tx-1';
    final first = BankTransaction(
      id: 'local-1',
      accountId: accountId,
      externalId: externalId,
      postedAtMillis: DateTime.fromMillisecondsSinceEpoch(0)
          .millisecondsSinceEpoch,
      amountCents: -500,
      rawDescription: 'Coffee',
      normalizedMerchant: 'COFFEE',
      pending: true,
    );
    final second = BankTransaction(
      id: 'local-2',
      accountId: accountId,
      externalId: externalId,
      postedAtMillis: DateTime.fromMillisecondsSinceEpoch(1000)
          .millisecondsSinceEpoch,
      amountCents: -500,
      rawDescription: 'Coffee',
      normalizedMerchant: 'COFFEE',
      pending: false,
    );

    final resolvedId = first.id; // repository keeps existing.id
    expect(resolvedId, 'local-1');
    expect(second.pending, isFalse);
    expect(second.externalId, first.externalId);
  });
}
