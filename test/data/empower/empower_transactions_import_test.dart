import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/data/empower/empower_transactions_import.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';

void main() {
  const k401 = 'k401';
  const empowerK401 = 1000905930;

  EmpowerTransaction contribution(int id, CalendarDay day, int cents) =>
      EmpowerTransaction(
        userTransactionId: id,
        userAccountId: empowerK401,
        postedDay: day,
        amountCents: cents,
        description: 'Fidelity Extended Market Index',
        transactionType: 'Employee contribution',
      );

  BankTransaction existingRow(String id, String externalId, CalendarDay day) =>
      BankTransaction(
        id: id,
        accountId: k401,
        externalId: externalId,
        postedAtMillis: day.localMidnightMillis,
        amountCents: 6522,
        rawDescription: '401(k) contribution · Fidelity Extended Market Index',
        normalizedMerchant:
            '401(K) CONTRIBUTION · FIDELITY EXTENDED MARKET INDEX',
        pending: false,
      );

  final import = EmpowerTransactionsImport(
    mappingByEmpowerAccountId: {
      empowerK401: const EmpowerAccountMapping(
        appAccountId: k401,
        label: '401(k) contribution',
      ),
    },
  );
  final payday = CalendarDay.of(2026, 7, 10);

  test(
    'a pair with one survivor re-keys the survivor and inserts the other',
    () {
      final plan = import.plan(
        incoming: [
          contribution(1, payday, 6522),
          contribution(2, payday, 6522),
        ],
        existing: [existingRow('old', 'empower:5d6357d7ad9c5f00', payday)],
        importedAtMillis: 0,
      );
      expect(plan.externalIdByAdoptedTransactionId, {'old': 'empower:1'});
      expect(plan.inserts.single.externalId, 'empower:2');
      expect(
        plan.inserts.single.rawDescription,
        '401(k) contribution · Fidelity Extended Market Index',
      );
    },
  );

  test('a row the live feed recorded a day later is left alone', () {
    final plan = import.plan(
      incoming: [contribution(1, payday, 6522)],
      existing: [existingRow('feed', 'TRN-1', payday.plusDays(1))],
      importedAtMillis: 0,
    );
    expect(plan.inserts, isEmpty);
    expect(plan.recordedByOtherSource.single.userTransactionId, 1);
  });

  test('re-running the same import changes nothing', () {
    final plan = import.plan(
      incoming: [contribution(1, payday, 6522)],
      existing: [existingRow('done', 'empower:1', payday)],
      importedAtMillis: 0,
    );
    expect(plan.alreadyImportedCount, 1);
    expect(plan.inserts, isEmpty);
    expect(plan.externalIdByAdoptedTransactionId, isEmpty);
  });

  test('buys and dividends inside the account are not imported by default', () {
    final plan = import.plan(
      incoming: [
        EmpowerTransaction(
          userTransactionId: 3,
          userAccountId: empowerK401,
          postedDay: payday,
          amountCents: 1200,
          description: 'Fidelity Extended Market Index',
          transactionType: 'Reinvest Dividend',
        ),
      ],
      existing: const [],
      importedAtMillis: 0,
    );
    expect(plan.inserts, isEmpty);
  });
}
