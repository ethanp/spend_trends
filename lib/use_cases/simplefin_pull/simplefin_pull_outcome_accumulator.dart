import 'package:spend_trends/use_cases/simplefin_pull/simplefin_account_mapper.dart';
import 'package:spend_trends/data/simplefin/simplefin_models.dart';
import 'package:spend_trends/data/repositories/simplefin_pull_history.dart';

/// Accumulates per-account pull outcomes for history journaling.
class SimpleFinPullOutcomeAccumulator() {
  final Map<String, SimpleFinPullAccountDraft> _byExternalId = {};

  List<SimpleFinPullAccountDraft> get drafts => _byExternalId.values.toList();

  int get accountCount => _byExternalId.length;

  void recordAccount({
    required SimpleFinAccount remoteAccount,
    required String localAccountId,
    required int newlyInsertedCount,
    required Iterable<SimpleFinError> authErrors,
    required List<SimpleFinError> bridgeErrors,
  }) {
    final draft = _byExternalId.putIfAbsent(
      remoteAccount.id,
      () => SimpleFinPullAccountDraft(
        accountExternalId: remoteAccount.id,
        accountLabel: SimpleFinAccountMapper.labelFor(remoteAccount),
      ),
    );
    draft.accountId = localAccountId;
    draft.accountExternalId = remoteAccount.id;
    draft.connId = remoteAccount.connId;
    draft.accountLabel = SimpleFinAccountMapper.labelFor(remoteAccount);
    draft.addTransactions(newlyInsertedCount);

    if (SimpleFinAccountMapper.needsRelink(
      remoteAccount: remoteAccount,
      authErrors: authErrors,
    )) {
      draft.mergeStatus(
        SimpleFinPullAccountStatus.needsRelink,
        'Authentication required — re-link in SimpleFIN',
      );
    }

    for (final error in bridgeErrors) {
      if (error.isAuthFailure) continue;
      final matchesAccount = error.accountId == remoteAccount.id;
      final matchesConn =
          error.connId != null && error.connId == remoteAccount.connId;
      if (!matchesAccount && !matchesConn) continue;
      draft.mergeStatus(SimpleFinPullAccountStatus.error, error.message);
    }
  }

  void recordErrorOnlyAccounts(List<SimpleFinError> bridgeErrors) {
    for (final error in bridgeErrors) {
      final externalId = error.accountId;
      if (externalId == null || externalId.isEmpty) continue;
      if (_byExternalId.containsKey(externalId)) continue;
      final status = error.isAuthFailure
          ? SimpleFinPullAccountStatus.needsRelink
          : SimpleFinPullAccountStatus.error;
      _byExternalId[externalId] = SimpleFinPullAccountDraft(
        accountExternalId: externalId,
        connId: error.connId,
        accountLabel: externalId,
        status: status,
        errorMessage: error.message,
      );
    }
  }
}
