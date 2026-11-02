import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/data/copilot_csv/copilot_csv_parse.dart';
import 'package:spend_trends/use_cases/csv_import/in_progress_copilot_csv_import.dart';
import 'package:spend_trends/domain/transactions/merchant_normalize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stableCopilotExternalId', () {
    test('TitleCase and lowercase merchant names produce the same id', () {
      final titleCase = stableCopilotExternalId(
        dateText: '2024-06-15',
        name: 'Amazon.com*NZ8KV',
        amountText: '42.50',
        accountName: 'Venture X',
        accountMask: '1298',
      );
      final lowerCase = stableCopilotExternalId(
        dateText: '2024-06-15',
        name: 'amazon.com*nz8kv',
        amountText: '42.50',
        accountName: 'Venture X',
        accountMask: '1298',
      );
      expect(titleCase, lowerCase);
      expect(titleCase, startsWith('copilot:'));
    });

    test('different amounts produce different ids', () {
      final fortyTwo = stableCopilotExternalId(
        dateText: '2024-06-15',
        name: 'Coffee Shop',
        amountText: '42.50',
        accountName: 'Checking',
        accountMask: '1001',
      );
      final fortyThree = stableCopilotExternalId(
        dateText: '2024-06-15',
        name: 'Coffee Shop',
        amountText: '43.50',
        accountName: 'Checking',
        accountMask: '1001',
      );
      expect(fortyTwo, isNot(fortyThree));
    });
  });

  group('copilotContentPresenceKey', () {
    test('same account/day/amount/merchant fingerprint are equal', () {
      final postedAt = DateTime(2024, 6, 15, 14, 30);
      final left = copilotContentPresenceKey(
        accountId: 'acct-1',
        postedDay: postedAt.calendarDay,
        amountCents: -4250,
        normalizedMerchant: normalizeMerchant('Amazon.com*nz8kv'),
      );
      final right = copilotContentPresenceKey(
        accountId: 'acct-1',
        postedDay: DateTime(2024, 6, 15, 9, 0).calendarDay,
        amountCents: -4250,
        normalizedMerchant: normalizeMerchant('AMAZON.COM*NZ8964S40'),
      );
      expect(left, right);
    });

    test('different accounts produce different keys', () {
      final postedAt = DateTime(2024, 6, 15);
      final left = copilotContentPresenceKey(
        accountId: 'acct-1',
        postedDay: postedAt.calendarDay,
        amountCents: -1000,
        normalizedMerchant: 'coffee shop',
      );
      final right = copilotContentPresenceKey(
        accountId: 'acct-2',
        postedDay: postedAt.calendarDay,
        amountCents: -1000,
        normalizedMerchant: 'coffee shop',
      );
      expect(left, isNot(right));
    });
  });
}
