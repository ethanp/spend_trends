import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/services/simplefin/simplefin_bank_target.dart';
import 'package:spend_trends/services/simplefin/simplefin_models.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_progress.dart';

void main() {
  test('local accounts group into one target per bank', () {
    final banks = SimpleFinBankTarget.fromLocalAccounts([
      _account(id: '1', externalId: 'ext-chase-1', connId: 'chase', connName: 'Chase'),
      _account(id: '2', externalId: 'ext-chase-2', connId: 'chase', connName: 'Chase'),
      _account(
        id: '3',
        externalId: 'ext-cap1',
        connId: 'cap1',
        connName: 'Capital One',
      ),
      _account(id: '4', externalId: 'copilot:old', connId: 'copilot'),
    ]);

    expect(banks.map((bank) => bank.name).toList(), ['Capital One', 'Chase']);
    expect(
      banks.firstWhere((bank) => bank.name == 'Chase').accountIds,
      ['ext-chase-1', 'ext-chase-2'],
    );
  });

  test('account set uses the same bank key as local accounts', () {
    final banks = SimpleFinBankTarget.fromAccountSet(
      SimpleFinClientAccountSet.sample(),
    );
    expect(banks, hasLength(1));
    expect(banks.single.connectionId, 'id:CON-1');
    expect(banks.single.name, 'Chase');
    expect(banks.single.accountIds, ['acct-1']);
  });

  test('notYetFetching drops account ids already in flight', () {
    final extras = SimpleFinBankTarget.notYetFetching(
      accountSet: SimpleFinClientAccountSet.sample(secondAccount: true),
      fetchingIds: {'acct-1'},
    );
    expect(extras.single.accountIds, ['acct-2']);
    expect(extras.single.connectionId, 'id:CON-1');
  });

  test('received fraction is unknown until the response length is known', () {
    const waiting = SimpleFinBankLoad(connectionId: 'id:CON-1', name: 'Chase');
    const receiving = SimpleFinBankLoad(
      connectionId: 'id:CON-1',
      name: 'Chase',
      phase: SimpleFinBankLoadPhase.receiving,
      bytesReceived: 50,
    );
    const half = SimpleFinBankLoad(
      connectionId: 'id:CON-1',
      name: 'Chase',
      phase: SimpleFinBankLoadPhase.receiving,
      bytesReceived: 50,
      contentLength: 100,
    );
    const done = SimpleFinBankLoad(
      connectionId: 'id:CON-1',
      name: 'Chase',
      phase: SimpleFinBankLoadPhase.done,
    );

    expect(waiting.receivedFraction, 0);
    expect(receiving.receivedFraction, isNull);
    expect(half.receivedFraction, 0.5);
    expect(done.receivedFraction, 1);
  });
}

Account _account({
  required String id,
  required String externalId,
  String? connId,
  String? connName,
}) {
  return Account(
    id: id,
    externalId: externalId,
    name: 'Checking',
    currency: 'USD',
    balanceCents: 0,
    connId: connId,
    connName: connName,
    status: AccountStatus.ok,
  );
}

extension SimpleFinClientAccountSet on SimpleFinAccountSet {
  static SimpleFinAccountSet sample({bool secondAccount = false}) {
    return SimpleFinAccountSet(
      errors: const [],
      accounts: [
        const SimpleFinAccount(
          id: 'acct-1',
          name: 'Checking',
          currency: 'USD',
          balance: '1',
          balanceDate: 0,
          connId: 'CON-1',
          connName: 'Chase',
          transactions: [],
        ),
        if (secondAccount)
          const SimpleFinAccount(
            id: 'acct-2',
            name: 'Savings',
            currency: 'USD',
            balance: '2',
            balanceDate: 0,
            connId: 'CON-1',
            connName: 'Chase',
            transactions: [],
          ),
      ],
    );
  }
}
