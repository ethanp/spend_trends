import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/services/simplefin/simplefin_models.dart';

/// One bank to fetch from SimpleFIN, with the account ids that belong to it.
class const SimpleFinBankTarget({
  required final String connectionId,
  required final String name,
  required final List<String> accountIds,
}) {
  static List<SimpleFinBankTarget> fromLocalAccounts(List<Account> accounts) {
    final grouped = <String, List<Account>>{};
    for (final account in accounts) {
      if (account.isCopilot || account.externalId.isEmpty) continue;
      grouped.putIfAbsent(account.institutionGroupKey, () => []).add(account);
    }
    return _sorted([
      for (final group in grouped.values)
        SimpleFinBankTarget(
          connectionId: group.first.institutionGroupKey,
          name: group.first.institutionDisplayName,
          accountIds: [
            for (final account in group) account.externalId,
          ],
        ),
    ]);
  }

  static List<SimpleFinBankTarget> fromAccountSet(SimpleFinAccountSet accountSet) {
    return _groupedTargets(accountSet.accounts);
  }

  /// Banks or extra accounts in [accountSet] whose ids are not already in [fetchingIds].
  static List<SimpleFinBankTarget> notYetFetching({
    required SimpleFinAccountSet accountSet,
    required Set<String> fetchingIds,
  }) {
    final unseen = [
      for (final account in accountSet.accounts)
        if (account.id.isNotEmpty && !fetchingIds.contains(account.id)) account,
    ];
    return _groupedTargets(unseen);
  }

  static List<SimpleFinBankTarget> _groupedTargets(
    List<SimpleFinAccount> accounts,
  ) {
    final grouped = <String, List<SimpleFinAccount>>{};
    for (final account in accounts) {
      if (account.id.isEmpty) continue;
      final connectionId = Account.institutionGroupKeyFor(
        connId: account.connId,
        connName: account.connName,
      );
      grouped.putIfAbsent(connectionId, () => []).add(account);
    }
    return _sorted([
      for (final group in grouped.values)
        SimpleFinBankTarget(
          connectionId: Account.institutionGroupKeyFor(
            connId: group.first.connId,
            connName: group.first.connName,
          ),
          name: _bankName(group.first),
          accountIds: [for (final account in group) account.id],
        ),
    ]);
  }

  static String _bankName(SimpleFinAccount account) {
    final name = account.connName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final connectionId = account.connId?.trim();
    if (connectionId != null && connectionId.isNotEmpty) return connectionId;
    return 'Other';
  }

  static List<SimpleFinBankTarget> _sorted(List<SimpleFinBankTarget> banks) {
    final sorted = [...banks];
    sorted.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return sorted;
  }
}
