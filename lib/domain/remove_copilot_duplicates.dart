import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/foundation.dart';

const _log = ELogger('RemoveCopilotDuplicates');

class const RemoveCopilotDuplicatesResult({
  required final int deletedCopilotCount,
  required final int linkedAccountMasks,
  final int deletedSameAccountCount = 0,
});

/// In-memory SimpleFIN matcher used by duplicate removal and Copilot CSV import.
class MatchingSimplefinCharges._({
  required final Map<String, String> _copilotLinkKeyByAccountId,
  required final Map<String, List<BankTransaction>> _simplefinByGroupKey,
  required final int linkCount,
}) {
  final Set<String> _matchedSimplefinIds = {};
  bool get isEmpty => linkCount == 0;

  factory from({
    required List<Account> accounts,
    required List<BankTransaction> transactions,
  }) {
    final accountsById = {for (final account in accounts) account.id: account};
    final links = _AccountLinks.fromAccounts(accounts);
    final simplefinByGroupKey = <String, List<BankTransaction>>{};
    for (final transaction in transactions) {
      final account = accountsById[transaction.accountId];
      if (account == null || account.isCopilot) continue;
      final linkKeys = links.keysForSimplefin(account);
      if (linkKeys.isEmpty) continue;
      final dayKey = transaction.postedAt.dayKey;
      for (final linkKey in linkKeys) {
        final groupKey = '$linkKey|$dayKey|${transaction.amountCents}';
        simplefinByGroupKey.putIfAbsent(groupKey, () => []).add(transaction);
      }
    }
    return MatchingSimplefinCharges._(
      copilotLinkKeyByAccountId: links.copilotKeyByAccountId,
      simplefinByGroupKey: simplefinByGroupKey,
      linkCount: links.linkCount,
    );
  }

  /// Best unmatched SimpleFIN charge for a Copilot-shaped row, or null.
  BankTransaction? takeMatch({
    required String copilotAccountId,
    required DateTime postedAt,
    required int amountCents,
    required String normalizedMerchant,
  }) {
    final match = findMatch(
      copilotAccountId: copilotAccountId,
      postedAt: postedAt,
      amountCents: amountCents,
      normalizedMerchant: normalizedMerchant,
      unmatchedOnly: true,
    );
    if (match == null) return null;
    _matchedSimplefinIds.add(match.id);
    return match;
  }

  /// Like [takeMatch] but does not reserve the SimpleFIN row.
  BankTransaction? findMatch({
    required String copilotAccountId,
    required DateTime postedAt,
    required int amountCents,
    required String normalizedMerchant,
    bool unmatchedOnly = true,
  }) {
    final linkKey = _copilotLinkKeyByAccountId[copilotAccountId];
    if (linkKey == null) return null;
    final groupKey = '$linkKey|${postedAt.dayKey}|$amountCents';
    final candidates = _simplefinByGroupKey[groupKey];
    if (candidates == null) return null;

    final available = [
      for (final candidate in candidates)
        if (!unmatchedOnly || !_matchedSimplefinIds.contains(candidate.id))
          candidate,
    ];
    return bestMerchantMatch(
      normalizedMerchant: normalizedMerchant,
      candidates: available,
    );
  }

  /// Refresh Copilot→link keys after a new Copilot account is created mid-import.
  void registerAccounts(List<Account> accounts) {
    final links = _AccountLinks.fromAccounts(accounts);
    _copilotLinkKeyByAccountId
      ..clear()
      ..addAll(links.copilotKeyByAccountId);
  }
}

/// Removes Copilot rows that duplicate SimpleFIN charges on the same card/account.
///
/// Links accounts by explicit [Account.belongsToAccountId] or by trailing
/// 4-digit mask. Keeps SimpleFIN as canonical and copies the Copilot note
/// onto the matching charge; rules categorize both rows the same way.
class RemoveCopilotDuplicates({
  required final AccountsRepository _accountsRepository,
  required final TransactionsRepository _transactionsRepository,
}) {
  Future<RemoveCopilotDuplicatesResult> run() async {
    final crossAccount = await _removeLinkedCopilotDuplicates();
    final sameAccountDeleted = await removeSameAccountDuplicates();
    return RemoveCopilotDuplicatesResult(
      deletedCopilotCount: crossAccount.deletedCopilotCount,
      linkedAccountMasks: crossAccount.linkedAccountMasks,
      deletedSameAccountCount: sameAccountDeleted,
    );
  }

  /// Same account + day + amount + merchant fingerprint → keep one, delete rest.
  Future<int> removeSameAccountDuplicates() async {
    final transactions = await _transactionsRepository.listAll();
    final buckets = <String, List<BankTransaction>>{};
    for (final transaction in transactions) {
      final fingerprint = merchantFingerprint(transaction.normalizedMerchant);
      if (fingerprint.isEmpty) continue;
      final key =
          '${transaction.accountId}|${transaction.postedAt.dayKey}|'
          '${transaction.amountCents}|$fingerprint';
      buckets.putIfAbsent(key, () => []).add(transaction);
    }

    final idsToDelete = <String>{};
    var notesCopied = 0;

    for (final bucket in buckets.values) {
      if (bucket.length < 2) continue;
      bucket.sort(_compareKeepPreferred);
      final keeper = bucket.first;
      for (final duplicate in bucket.skip(1)) {
        final duplicateNote = duplicate.note?.trim() ?? '';
        if (duplicateNote.isNotEmpty && (keeper.note?.trim() ?? '').isEmpty) {
          await _transactionsRepository.setNote(
            transactionId: keeper.id,
            note: duplicateNote,
          );
          notesCopied++;
        }
        idsToDelete.add(duplicate.id);
      }
    }

    for (final transactionId in idsToDelete) {
      await _transactionsRepository.deleteTransaction(transactionId);
    }

    _log.log(
      'Removed ${idsToDelete.length} same-account duplicates '
      '(merged $notesCopied notes)',
    );
    return idsToDelete.length;
  }

  Future<RemoveCopilotDuplicatesResult> _removeLinkedCopilotDuplicates() async {
    final accounts = await _accountsRepository.listAccounts();
    final transactions = await _transactionsRepository.listAll();
    final accountsById = {for (final account in accounts) account.id: account};
    final matchingCharges = MatchingSimplefinCharges.from(
      accounts: accounts,
      transactions: transactions,
    );
    if (matchingCharges.isEmpty) {
      return const RemoveCopilotDuplicatesResult(
        deletedCopilotCount: 0,
        linkedAccountMasks: 0,
      );
    }

    final copilotIdsToDelete = <String>{};

    for (final transaction in transactions) {
      final account = accountsById[transaction.accountId];
      if (account == null || !account.isCopilot) continue;

      final match = matchingCharges.takeMatch(
        copilotAccountId: account.id,
        postedAt: transaction.postedAt,
        amountCents: transaction.amountCents,
        normalizedMerchant: transaction.normalizedMerchant,
      );
      if (match == null) continue;

      final noteToCopy = transaction.note?.trim() ?? '';
      if (noteToCopy.isNotEmpty) {
        final matchNote = match.note?.trim() ?? '';
        if (matchNote.isEmpty) {
          await _transactionsRepository.setNote(
            transactionId: match.id,
            note: noteToCopy,
          );
        }
      }

      copilotIdsToDelete.add(transaction.id);
    }

    for (final transactionId in copilotIdsToDelete) {
      await _transactionsRepository.deleteTransaction(transactionId);
    }

    _log.log(
      'Removed ${copilotIdsToDelete.length} Copilot duplicates across '
      '${matchingCharges.linkCount} linked accounts',
    );

    return RemoveCopilotDuplicatesResult(
      deletedCopilotCount: copilotIdsToDelete.length,
      linkedAccountMasks: matchingCharges.linkCount,
    );
  }

  /// Higher-quality row first (kept); weaker duplicates deleted.
  static int _compareKeepPreferred(
    BankTransaction left,
    BankTransaction right,
  ) {
    final scoreCompare = _keepScore(right)
        .compareTo(_keepScore(left)); // higher first
    if (scoreCompare != 0) return scoreCompare;
    final leftImported = left.importedAt ?? left.postedAt;
    final rightImported = right.importedAt ?? right.postedAt;
    final importedCompare = leftImported.compareTo(rightImported);
    if (importedCompare != 0) return importedCompare;
    return left.id.compareTo(right.id);
  }

  static int _keepScore(BankTransaction transaction) {
    var score = 0;
    if ((transaction.note?.trim() ?? '').isNotEmpty) score += 50;
    // Prefer live-bank rows over Copilot re-imports when external ids differ.
    if (!transaction.externalId.startsWith('copilot:')) score += 20;
    return score;
  }

  /// Trailing 4 digits from Copilot external id or account name.
  static String? accountMask(Account account) {
    if (account.isCopilot) {
      final parts = account.externalId.split(':');
      if (parts.length >= 3) {
        final mask = parts.last.trim();
        if (RegExp(r'^\d{4}$').hasMatch(mask)) return mask;
      }
    }
    final nameMatch = RegExp(r'(\d{4})\D*$').firstMatch(account.name.trim());
    return nameMatch?.group(1);
  }

  /// Copilot account id → link key used for duplicate matching.
  ///
  /// Explicit [Account.belongsToAccountId] uses `id:<parentId>`; shared
  /// last-4 masks use `mask:<digits>`.
  @visibleForTesting
  static Map<String, String> copilotLinkKeysForTest(List<Account> accounts) =>
      _AccountLinks.fromAccounts(accounts).copilotKeyByAccountId;
}

BankTransaction? bestMerchantMatch({
  required String normalizedMerchant,
  required List<BankTransaction> candidates,
}) {
  if (candidates.isEmpty) return null;

  final copilotFingerprint = merchantFingerprint(normalizedMerchant);
  if (candidates.length == 1) {
    // Linked account + same day + same amount is enough when unique.
    return candidates.first;
  }
  if (copilotFingerprint.isEmpty) return null;

  BankTransaction? bestMatch;
  var bestScore = 0;
  for (final candidate in candidates) {
    final score = _merchantSimilarity(
      copilotFingerprint,
      merchantFingerprint(candidate.normalizedMerchant),
    );
    if (score > bestScore) {
      bestScore = score;
      bestMatch = candidate;
    }
  }
  // Strong merchant overlap, or any overlap when picking among same-day/amount.
  if (bestScore >= 4) return bestMatch;
  if (bestScore > 0) return bestMatch;
  return null;
}

/// Shared prefix length, or length of the shorter string when one contains
/// the other.
int _merchantSimilarity(String left, String right) {
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right) return left.length;
  if (left.startsWith(right) || right.startsWith(left)) {
    return left.length < right.length ? left.length : right.length;
  }
  final minLength = left.length < right.length ? left.length : right.length;
  var sharedPrefix = 0;
  for (var index = 0; index < minLength; index++) {
    if (left.codeUnitAt(index) != right.codeUnitAt(index)) break;
    sharedPrefix++;
  }
  return sharedPrefix;
}

/// Explicit belongs-to pairs plus mask-intersection pairs for unlinked accounts.
class _AccountLinks({
  required final Map<String, String> copilotKeyByAccountId,
  required final Map<String, Set<String>> simplefinKeysByAccountId,
  required final int linkCount,
}) {
  bool get isEmpty => linkCount == 0;

  String? keyForCopilot(Account account) => copilotKeyByAccountId[account.id];

  Set<String> keysForSimplefin(Account account) =>
      simplefinKeysByAccountId[account.id] ?? const {};

  factory fromAccounts(List<Account> accounts) {
    final accountsById = {for (final account in accounts) account.id: account};
    final copilotKeyByAccountId = <String, String>{};
    final simplefinKeysByAccountId = <String, Set<String>>{};
    final linkedPairKeys = <String>{};

    for (final account in accounts) {
      final parentId = account.belongsToAccountId;
      if (!account.isCopilot || parentId == null) continue;
      final parent = accountsById[parentId];
      if (parent == null || parent.isCopilot) continue;
      final linkKey = 'id:$parentId';
      copilotKeyByAccountId[account.id] = linkKey;
      simplefinKeysByAccountId.putIfAbsent(parentId, () => {}).add(linkKey);
      linkedPairKeys.add(linkKey);
    }

    final copilotMasks = <String, List<Account>>{};
    final simplefinMasks = <String, List<Account>>{};
    for (final account in accounts) {
      if (account.isCopilot && account.belongsToAccountId != null) continue;
      final mask = RemoveCopilotDuplicates.accountMask(account);
      if (mask == null) continue;
      if (account.isCopilot) {
        copilotMasks.putIfAbsent(mask, () => []).add(account);
      } else {
        simplefinMasks.putIfAbsent(mask, () => []).add(account);
      }
    }

    for (final mask in copilotMasks.keys) {
      final simplefinAccounts = simplefinMasks[mask];
      if (simplefinAccounts == null || simplefinAccounts.isEmpty) continue;
      final linkKey = 'mask:$mask';
      for (final copilotAccount in copilotMasks[mask]!) {
        copilotKeyByAccountId.putIfAbsent(copilotAccount.id, () => linkKey);
      }
      for (final simplefinAccount in simplefinAccounts) {
        simplefinKeysByAccountId
            .putIfAbsent(simplefinAccount.id, () => {})
            .add(linkKey);
      }
      linkedPairKeys.add(linkKey);
    }

    return _AccountLinks(
      copilotKeyByAccountId: copilotKeyByAccountId,
      simplefinKeysByAccountId: simplefinKeysByAccountId,
      linkCount: linkedPairKeys.length,
    );
  }
}

/// Strips order-id noise so "AMAZON.COM*NZ8KV" ≈ "AMAZON.COM*NZ8964S40".
String merchantFingerprint(String merchant) {
  return merchant
      .toUpperCase()
      .replaceAll(RegExp(r'\*[A-Z0-9]+'), '')
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
