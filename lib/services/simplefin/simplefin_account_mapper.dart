import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/services/simplefin/simplefin_models.dart';
import 'package:spend_trends/services/sqlite/account_balance_snapshots_repository.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:uuid/uuid.dart';

/// Maps SimpleFIN remote accounts into local [Account] rows, saving each
/// pulled balance as that day's snapshot for net worth history.
class SimpleFinAccountMapper({
  required final AccountsRepository _accountsRepository,
  required final AccountBalanceSnapshotsRepository _snapshotsRepository,
  Uuid? uuid,
}) {
  final Uuid _uuid = uuid ?? const Uuid();

  static String labelFor(SimpleFinAccount remoteAccount) {
    final institution = remoteAccount.connName?.trim();
    if (institution != null && institution.isNotEmpty) {
      return '$institution · ${remoteAccount.name}';
    }
    return remoteAccount.name;
  }

  static bool needsRelink({
    required SimpleFinAccount remoteAccount,
    required Iterable<SimpleFinError> authErrors,
  }) {
    return authErrors.any(
      (error) => error.connId == null || error.connId == remoteAccount.connId,
    );
  }

  Future<String> upsertFromRemote({
    required SimpleFinAccount remoteAccount,
    required Iterable<SimpleFinError> authErrors,
    required DateTime syncedAt,
  }) async {
    final existing = await _accountsRepository.findByExternalId(
      remoteAccount.id,
    );
    final localId = existing?.id ?? _uuid.v4();
    final relink = needsRelink(
      remoteAccount: remoteAccount,
      authErrors: authErrors,
    );

    final draft = Account(
      id: localId,
      externalId: remoteAccount.id,
      name: remoteAccount.name,
      currency: remoteAccount.currency,
      balanceCents: remoteAccount.balance.asCents,
      balanceAsOf: remoteAccount.balanceDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              remoteAccount.balanceDate * 1000,
            )
          : null,
      connId: remoteAccount.connId,
      connName: remoteAccount.connName,
      lastSyncedAt: syncedAt,
      status: relink ? AccountStatus.needsRelink : AccountStatus.ok,
      statusMessage: relink
          ? 'Authentication required — re-link in SimpleFIN'
          : null,
      userLabel: existing?.userLabel,
      connUserLabel: existing?.connUserLabel,
      belongsToAccountId: existing?.belongsToAccountId,
    );
    await _accountsRepository.upsertAccount(
      draft.copyWith(
        kind: existing?.kind ?? AccountKindClassifier.classify(draft),
      ),
    );
    await _snapshotsRepository.recordDailyBalance(
      accountId: localId,
      balanceCents: draft.balanceCents,
      day: (draft.balanceAsOf ?? syncedAt).toLocal(),
    );
    return localId;
  }
}
