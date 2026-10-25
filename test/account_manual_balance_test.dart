import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';

void main() {
  final now = DateTime(2026, 10, 24);

  Account account({required String externalId, DateTime? balanceAsOf}) =>
      Account(
        id: 'account',
        externalId: externalId,
        name: 'HSA',
        currency: 'USD',
        balanceCents: 4810895,
        balanceAsOf: balanceAsOf,
        status: AccountStatus.ok,
      );

  test('manual balance recorded within 60 days is fresh', () {
    expect(
      account(
        externalId: 'manual:hsa',
        balanceAsOf: DateTime(2026, 9, 1),
      ).isManualBalanceStale(now),
      isFalse,
    );
  });

  test('manual balance older than 60 days is stale', () {
    expect(
      account(
        externalId: 'manual:hsa',
        balanceAsOf: DateTime(2025, 10, 20),
      ).isManualBalanceStale(now),
      isTrue,
    );
  });

  test('manual account with no balance recorded is stale', () {
    expect(account(externalId: 'manual:hsa').isManualBalanceStale(now), isTrue);
  });

  test('SimpleFIN balances are never flagged', () {
    expect(
      account(
        externalId: 'ACT-123',
        balanceAsOf: DateTime(2025, 1, 1),
      ).isManualBalanceStale(now),
      isFalse,
    );
  });
}
