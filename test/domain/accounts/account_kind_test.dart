import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountKindClassifier', () {
    test('classifies checking and savings by name', () {
      expect(_kind(name: 'Chase Checking'), AccountKind.checking);
      expect(_kind(name: 'High Yield Savings'), AccountKind.savings);
      expect(_kind(name: 'Money Market'), AccountKind.savings);
    });

    test('classifies investment including former tax-advantaged', () {
      expect(_kind(name: 'Roth IRA'), AccountKind.investment);
      expect(_kind(name: 'Traditional IRA'), AccountKind.investment);
      expect(_kind(name: '401(k)'), AccountKind.investment);
      expect(_kind(name: '529 College'), AccountKind.investment);
      expect(_kind(name: 'HSA'), AccountKind.investment);
      expect(
        _kind(name: 'Brokerage', connName: 'Schwab'),
        AccountKind.investment,
      );
      expect(
        _kind(name: 'Account', connName: 'M1', balanceCents: 100000),
        AccountKind.investment,
      );
    });

    test('classifies credit cards', () {
      expect(
        _kind(name: 'Chase Sapphire', balanceCents: -120000),
        AccountKind.creditCard,
      );
      expect(_kind(name: 'Amex Gold Card'), AccountKind.creditCard);
      expect(_kind(name: 'Visa Signature'), AccountKind.creditCard);
    });

    test('classifies loans including M1 margin', () {
      expect(_kind(name: 'Mortgage'), AccountKind.loans);
      expect(_kind(name: 'Car Loan'), AccountKind.loans);
      expect(
        _kind(name: 'Account', connName: 'M1', balanceCents: -50000),
        AccountKind.loans,
      );
      expect(_kind(name: 'Margin Loan', connName: 'M1'), AccountKind.loans);
    });

    test('classifies non-financial assets', () {
      expect(_kind(name: 'Home value'), AccountKind.nonFinancialAssets);
      expect(_kind(name: 'Vehicle'), AccountKind.nonFinancialAssets);
    });
  });
}

AccountKind _kind({
  required String name,
  String? connName,
  int balanceCents = 0,
}) {
  return AccountKindClassifier.classify(
    Account(
      id: 'id',
      externalId: 'ext',
      name: name,
      currency: 'USD',
      balanceCents: balanceCents,
      connName: connName,
      status: AccountStatus.ok,
    ),
  );
}
