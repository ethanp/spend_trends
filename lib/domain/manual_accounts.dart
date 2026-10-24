import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/services/sqlite/account_balance_snapshots_repository.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:uuid/uuid.dart';

/// Accounts valued by hand: institutions SimpleFIN cannot reach. Each
/// balance update is a dated snapshot; the newest is the account's balance.
class ManualAccounts({
  required final AccountsRepository _accountsRepository,
  required final AccountBalanceSnapshotsRepository _snapshotsRepository,
}) {
  static const _uuid = Uuid();

  /// Creates a manual account, or turns the history-only account
  /// [fromHistoryAccountId] into one so its imported transactions stay.
  Future<Account> create({
    required String name,
    required AccountKind kind,
    String? institution,
    String? fromHistoryAccountId,
  }) async {
    final externalId = 'manual:${_uuid.v4()}';
    if (fromHistoryAccountId != null) {
      final Account? historyAccount = await _accountsRepository.findById(
        fromHistoryAccountId,
      );
      if (historyAccount == null || !historyAccount.isHistoryImport) {
        throw ArgumentError('$fromHistoryAccountId is not a history account.');
      }
      await _accountsRepository.reidentify(
        accountId: historyAccount.id,
        externalId: externalId,
        name: name,
        kind: kind,
        institution: institution,
      );
    } else {
      await _accountsRepository.upsertAccount(
        Account(
          id: _uuid.v4(),
          externalId: externalId,
          name: name,
          currency: 'USD',
          balanceCents: 0,
          status: AccountStatus.ok,
          connName: institution,
          kind: kind,
        ),
      );
    }
    return (await _accountsRepository.findByExternalId(externalId))!;
  }

  /// Records [balanceCents] on [recordedOn]; it becomes the account's
  /// balance unless a later snapshot already exists.
  Future<void> recordBalance({
    required Account account,
    required int balanceCents,
    required DateTime recordedOn,
  }) async {
    if (!account.isManual) {
      throw ArgumentError('${account.displayName} is not a manual account.');
    }
    final day = recordedOn.startOfDay;
    await _snapshotsRepository.insert(
      AccountBalanceSnapshot(
        id: _uuid.v4(),
        accountId: account.id,
        balanceCents: balanceCents,
        recordedOn: day,
      ),
    );
    await _adoptNewestSnapshot(account.id);
  }

  /// Removes one recorded balance; the newest remaining becomes the balance.
  Future<void> deleteBalance(AccountBalanceSnapshot snapshot) async {
    await _snapshotsRepository.delete(snapshot.id);
    await _adoptNewestSnapshot(snapshot.accountId);
  }

  Future<void> _adoptNewestSnapshot(String accountId) async {
    AccountBalanceSnapshot? newest;
    for (final snapshot in await _snapshotsRepository.listAll()) {
      if (snapshot.accountId == accountId) newest = snapshot;
    }
    await _accountsRepository.setBalance(
      accountId: accountId,
      balanceCents: newest?.balanceCents ?? 0,
      asOf: newest?.recordedOn,
    );
  }
}

final manualAccountsProvider = FutureProvider<ManualAccounts>((ref) async {
  return ManualAccounts(
    accountsRepository: await ref.watch(accountsRepositoryProvider.future),
    snapshotsRepository: await ref.watch(
      accountBalanceSnapshotsRepositoryProvider.future,
    ),
  );
});
