import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/empower_recorded_rows.dart';
import 'package:spend_trends/domain/transaction.dart';

void main() {
  final payday = CalendarDay.of(2026, 7, 10);

  BankTransaction row(String externalId, {int dayOffset = 0}) =>
      BankTransaction(
        id: externalId,
        accountId: 'k401',
        externalId: externalId,
        postedAtMillis: payday.plusDays(dayOffset).localMidnightMillis,
        amountCents: 6522,
        rawDescription: 'Fidelity Extended Market Index',
        normalizedMerchant: 'FIDELITY EXTENDED MARKET INDEX',
        pending: false,
      );

  test('the feed copy of each imported row of a pair is skipped once', () {
    final recordedRows = EmpowerRecordedRows.forAccount([
      row('empower:1'),
      row('empower:2'),
    ]);
    expect(recordedRows.claim(row('TRN-a', dayOffset: 1)), isTrue);
    expect(recordedRows.claim(row('TRN-b', dayOffset: 1)), isTrue);
    expect(recordedRows.claim(row('TRN-c', dayOffset: 1)), isFalse);
  });

  test('an imported row the feed already has is not claimed again', () {
    final recordedRows = EmpowerRecordedRows.forAccount([
      row('empower:1'),
      row('TRN-a'),
    ]);
    expect(recordedRows.claim(row('TRN-b')), isFalse);
  });

  test('a row more than two days away is a different contribution', () {
    final recordedRows = EmpowerRecordedRows.forAccount([row('empower:1')]);
    expect(recordedRows.claim(row('TRN-a', dayOffset: 3)), isFalse);
  });
}
