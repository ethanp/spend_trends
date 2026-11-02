import 'package:flutter_test/flutter_test.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/ui/banks/bank_accounts_by_institution.dart';

void main() {
  test('sorts each institution by absolute balance, largest first', () {
    final groups = BankAccountsByInstitution.groups([
      _account(id: 'checking', name: 'Checking', balanceCents: 120000),
      _account(id: 'card', name: 'Credit Card', balanceCents: -450000),
      _account(id: 'savings', name: 'Savings', balanceCents: 80000),
    ]);

    expect(groups, hasLength(1));
    expect(groups.first.accounts.mapL((account) => account.id), [
      'card',
      'checking',
      'savings',
    ]);
  });
}

Account _account({
  required String id,
  required String name,
  required int balanceCents,
}) {
  return Account(
    id: id,
    externalId: id,
    name: name,
    currency: 'USD',
    balanceCents: balanceCents,
    connId: 'ally',
    connName: 'Ally',
    status: AccountStatus.ok,
  );
}
