import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/remove_copilot_duplicates.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('same-account duplicates', () {
    BankTransaction row(String id, String externalId) => BankTransaction(
      id: id,
      accountId: 'k401',
      externalId: externalId,
      postedAtMillis: DateTime(2026, 7, 10).millisecondsSinceEpoch,
      amountCents: 6522,
      rawDescription: '401(k) contribution · Fidelity Extended Market Index',
      normalizedMerchant:
          '401(K) CONTRIBUTION · FIDELITY EXTENDED MARKET INDEX',
      pending: false,
    );

    test('a pair one source reported under two ids is two transactions', () {
      expect(
        RemoveCopilotDuplicates.sameAccountDuplicates([
          row('first', 'empower:100013446785351'),
          row('second', 'empower:100013446785354'),
        ]),
        isEmpty,
      );
    });

    test('a Copilot re-import of a live-feed row is a duplicate', () {
      final duplicates = RemoveCopilotDuplicates.sameAccountDuplicates([
        row('feed', 'TRN-1'),
        row('copilot', 'copilot:k401:2026-07-10:6522'),
      ]);
      expect(duplicates.single.duplicate.id, 'copilot');
      expect(duplicates.single.keeper.id, 'feed');
    });
  });

  group('merchantFingerprint', () {
    test('strips amazon order suffixes', () {
      expect(
        merchantFingerprint('Amazon.com*nz8kv'),
        merchantFingerprint('Amazon.com*nz8964s40'),
      );
    });

    test('normalizes case and punctuation', () {
      expect(
        merchantFingerprint("Senior Pepe's Cocina"),
        merchantFingerprint('SENIOR PEPE\'S COCINA'),
      );
    });

    test('collapses Amazon order-id variants used in same-account dupes', () {
      expect(
        merchantFingerprint('Amazon.com*hy1oo'),
        merchantFingerprint('AMAZON.COM*HY1OO'),
      );
    });
  });

  group('accountMask', () {
    test('reads Copilot external id mask', () {
      expect(
        RemoveCopilotDuplicates.accountMask(
          const Account(
            id: '1',
            externalId: 'copilot:Venture X:1298',
            name: 'Venture X ·1298',
            currency: 'USD',
            balanceCents: 0,
            status: AccountStatus.ok,
          ),
        ),
        '1298',
      );
    });

    test('reads trailing digits from SimpleFIN name', () {
      expect(
        RemoveCopilotDuplicates.accountMask(
          const Account(
            id: '2',
            externalId: 'ACT-abc',
            name: 'Venture X (1298)',
            currency: 'USD',
            balanceCents: 0,
            status: AccountStatus.ok,
          ),
        ),
        '1298',
      );
    });
  });

  group('explicit belongs-to linking', () {
    test('belongsToAccountId links without a shared mask', () {
      const parent = Account(
        id: 'parent',
        externalId: 'ACT-parent',
        name: 'Sapphire Reserve',
        currency: 'USD',
        balanceCents: -1000,
        status: AccountStatus.ok,
      );
      const child = Account(
        id: 'child',
        externalId: 'copilot:Old Card:4242',
        name: 'Old Card ·4242',
        currency: 'USD',
        balanceCents: 0,
        status: AccountStatus.ok,
        belongsToAccountId: 'parent',
      );
      expect(child.hasParent, isTrue);
      expect(child.countsTowardNetWorth, isFalse);
      expect(parent.countsTowardNetWorth, isTrue);
      expect(RemoveCopilotDuplicates.accountMask(parent), isNull);

      final linkKeys = RemoveCopilotDuplicates.copilotLinkKeysForTest([
        parent,
        child,
      ]);
      expect(linkKeys['child'], 'id:parent');
    });
  });

  group('bestMerchantMatch', () {
    test(
      'accepts unique same-day amount candidate without merchant overlap',
      () {
        final twin = bestMerchantMatch(
          normalizedMerchant: 'COMPLETELY DIFFERENT',
          candidates: [
            BankTransaction(
              id: 'sf1',
              accountId: 'a',
              externalId: 'e',
              postedAtMillis: DateTime(2026, 6, 30).millisecondsSinceEpoch,
              amountCents: -5000,
              rawDescription: 'OTHER',
              normalizedMerchant: 'OTHER',
              pending: false,
            ),
          ],
        );
        expect(twin?.id, 'sf1');
      },
    );

    test(
      'requires merchant overlap when multiple candidates share day+amount',
      () {
        final twin = bestMerchantMatch(
          normalizedMerchant: 'UBER TRIP',
          candidates: [
            BankTransaction(
              id: 'lyft',
              accountId: 'a',
              externalId: 'e1',
              postedAtMillis: DateTime(2026, 6, 30).millisecondsSinceEpoch,
              amountCents: -5000,
              rawDescription: 'LYFT',
              normalizedMerchant: 'LYFT',
              pending: false,
            ),
            BankTransaction(
              id: 'uber',
              accountId: 'a',
              externalId: 'e2',
              postedAtMillis: DateTime(2026, 6, 30).millisecondsSinceEpoch,
              amountCents: -5000,
              rawDescription: 'UBER',
              normalizedMerchant: 'UBER TRIP HELP',
              pending: false,
            ),
          ],
        );
        expect(twin?.id, 'uber');
      },
    );
  });
}
