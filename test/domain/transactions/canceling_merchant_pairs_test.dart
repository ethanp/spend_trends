import 'package:spend_trends/domain/transactions/canceling_merchant_pairs.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CancelingMerchantPairs', () {
    test('hides equal opposite amounts same day merchant account', () {
      final buy = _txn(
        id: 'buy',
        amountCents: -52271,
        merchant: 'VANGUARD TOTAL BOND',
        day: DateTime(2026, 6, 30, 12),
      );
      final sell = _txn(
        id: 'sell',
        amountCents: 52271,
        merchant: 'VANGUARD TOTAL BOND',
        day: DateTime(2026, 6, 30, 18),
      );
      final keep = _txn(
        id: 'keep',
        amountCents: -1000,
        merchant: 'COFFEE SHOP',
        day: DateTime(2026, 6, 30),
      );

      expect(CancelingMerchantPairs.transactionIds([buy, sell, keep]), {
        'buy',
        'sell',
      });
      expect(
        CancelingMerchantPairs.excludingCancelingPairs([buy, sell, keep])
            .map((t) => t.id),
        ['keep'],
      );
    });

    test('pairs only min(inflow, outflow) when counts differ', () {
      final a = _txn(id: 'a', amountCents: 1888, merchant: 'SCHWAB ETF');
      final b = _txn(id: 'b', amountCents: -1888, merchant: 'SCHWAB ETF');
      final c = _txn(id: 'c', amountCents: -1888, merchant: 'SCHWAB ETF');

      expect(CancelingMerchantPairs.transactionIds([a, b, c]), {'a', 'b'});
      expect(
        CancelingMerchantPairs.excludingCancelingPairs([a, b, c])
            .map((t) => t.id),
        ['c'],
      );
    });

    test('does not pair across different days', () {
      final monday = _txn(
        id: 'mon',
        amountCents: -100,
        merchant: 'FUND',
        day: DateTime(2026, 6, 29),
      );
      final tuesday = _txn(
        id: 'tue',
        amountCents: 100,
        merchant: 'FUND',
        day: DateTime(2026, 6, 30),
      );
      expect(CancelingMerchantPairs.transactionIds([monday, tuesday]), isEmpty);
    });

    test('does not pair across different accounts', () {
      final left = _txn(
        id: 'left',
        accountId: 'ira',
        amountCents: -100,
        merchant: 'FUND',
      );
      final right = _txn(
        id: 'right',
        accountId: 'brokerage',
        amountCents: 100,
        merchant: 'FUND',
      );
      expect(CancelingMerchantPairs.transactionIds([left, right]), isEmpty);
    });

    test('does not pair different merchants on non-investment accounts', () {
      final bond = _txn(id: 'bond', amountCents: -500, merchant: 'BOND');
      final mm = _txn(id: 'mm', amountCents: 500, merchant: 'MONEY MARKET');
      final near = _txn(id: 'near', amountCents: 501, merchant: 'BOND');
      expect(CancelingMerchantPairs.transactionIds([bond, mm, near]), isEmpty);
    });

    test('investment accounts pair different fund names same day amount', () {
      final sellMm = _txn(
        id: 'sell-mm',
        accountId: 'rollover-ira',
        amountCents: -1953,
        merchant: 'VANGUARD FEDERAL MONEY MARKET INVESTOR CL',
        day: DateTime(2026, 5, 4),
      );
      final buyBond = _txn(
        id: 'buy-bond',
        accountId: 'rollover-ira',
        amountCents: 1953,
        merchant: 'VANGUARD INTERMEDIATE TERM INVEST GRADE INVESTOR CL',
        day: DateTime(2026, 5, 4),
      );
      final keep = _txn(
        id: 'keep',
        accountId: 'rollover-ira',
        amountCents: 3606,
        merchant: 'VANGUARD FEDERAL MONEY MARKET INVESTOR CL',
        day: DateTime(2026, 5, 4),
      );

      expect(
        CancelingMerchantPairs.transactionIds(
          [sellMm, buyBond, keep],
          investmentAccountIds: {'rollover-ira'},
        ),
        {'sell-mm', 'buy-bond'},
      );
    });

    test('investment accounts pair across settlement days within window', () {
      final sell = _txn(
        id: 'sell',
        accountId: 'roth',
        amountCents: -3606,
        merchant: 'VANGUARD TOTAL STOCK MARKET INDEX ADMIRAL CL',
        day: DateTime(2026, 5, 1),
      );
      final credit = _txn(
        id: 'credit',
        accountId: 'roth',
        amountCents: 3606,
        merchant: 'VANGUARD FEDERAL MONEY MARKET INVESTOR CL',
        day: DateTime(2026, 5, 4),
      );
      expect(
        CancelingMerchantPairs.transactionIds(
          [sell, credit],
          investmentAccountIds: {'roth'},
        ),
        {'sell', 'credit'},
      );
    });

    test('investment accounts do not pair beyond settlement window', () {
      final sell = _txn(
        id: 'sell',
        accountId: 'roth',
        amountCents: -3606,
        merchant: 'VANGUARD TOTAL STOCK',
        day: DateTime(2026, 5, 1),
      );
      final credit = _txn(
        id: 'credit',
        accountId: 'roth',
        amountCents: 3606,
        merchant: 'VANGUARD FEDERAL MONEY MARKET',
        day: DateTime(2026, 5, 10),
      );
      expect(
        CancelingMerchantPairs.transactionIds(
          [sell, credit],
          investmentAccountIds: {'roth'},
        ),
        isEmpty,
      );
    });

    test('investment pairs nearest dates when multiple candidates', () {
      final earlySell = _txn(
        id: 'early-sell',
        accountId: 'roth',
        amountCents: -1000,
        merchant: 'FUND A',
        day: DateTime(2026, 5, 1),
      );
      final lateSell = _txn(
        id: 'late-sell',
        accountId: 'roth',
        amountCents: -1000,
        merchant: 'FUND B',
        day: DateTime(2026, 5, 6),
      );
      final buy = _txn(
        id: 'buy',
        accountId: 'roth',
        amountCents: 1000,
        merchant: 'FUND C',
        day: DateTime(2026, 5, 7),
      );
      expect(
        CancelingMerchantPairs.transactionIds(
          [earlySell, lateSell, buy],
          investmentAccountIds: {'roth'},
        ),
        {'late-sell', 'buy'},
      );
    });
  });
}

BankTransaction _txn({
  required String id,
  required int amountCents,
  required String merchant,
  String accountId = 'acct',
  DateTime? day,
}) {
  return BankTransaction(
    id: id,
    accountId: accountId,
    externalId: id,
    postedAtMillis: (day ?? DateTime(2026, 6, 30)).millisecondsSinceEpoch,
    amountCents: amountCents,
    rawDescription: merchant,
    normalizedMerchant: merchant,
    pending: false,
  );
}
