import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/util/merchant_normalize.dart';
import 'package:uuid/uuid.dart';

/// One row of Empower's `getUserTransactions` response.
class const EmpowerTransaction({
  required final int userTransactionId,
  required final int userAccountId,
  required final CalendarDay postedDay,
  required final int amountCents,
  required final String description,
  required final String transactionType,
}) {
  factory fromJson(Map<String, dynamic> json) {
    final [year, month, day] = (json['transactionDate'] as String)
        .split('-')
        .map(int.parse)
        .toList();
    final int magnitudeCents = ((json['amount'] as num) * 100).round().abs();
    return EmpowerTransaction(
      userTransactionId: json['userTransactionId'] as int,
      userAccountId: json['userAccountId'] as int,
      postedDay: CalendarDay.of(year, month, day),
      amountCents: json['isCredit'] == true ? magnitudeCents : -magnitudeCents,
      description: (json['description'] as String).trim(),
      transactionType: (json['transactionType'] as String).trim(),
    );
  }

  /// Empower's own id, so a re-import of the same row is recognized.
  String get externalId => 'empower:$userTransactionId';

  /// Contributions are the cash flow the app tracks; buys, dividends, and
  /// share moves inside the account are not.
  bool get isContribution =>
      transactionType.toLowerCase().contains('contribution');
}

/// Where an Empower account's rows land: the app account, and the label
/// that starts each description (`401(k) contribution · <fund>`), which the
/// categorization rules match.
class const EmpowerAccountMapping({
  required final String appAccountId,
  required final String label,
}) {
  factory fromJson(Map<String, dynamic> json) => EmpowerAccountMapping(
    appAccountId: json['accountId'] as String,
    label: json['label'] as String,
  );

  Map<String, Object?> toJson() => {'accountId': appAccountId, 'label': label};
}

/// What importing does, worked out before anything is written.
class const EmpowerImportPlan({
  /// Rows no source has recorded yet.
  required final List<BankTransaction> inserts,

  /// Existing rows from an earlier Empower import under another id scheme,
  /// by app transaction id → the Empower id they take now.
  required final Map<String, String> externalIdByAdoptedTransactionId,
  required final int alreadyImportedCount,

  /// Empower rows another source (the live bank feed) already recorded.
  required final List<EmpowerTransaction> recordedByOtherSource,

  /// Earlier Empower imports on mapped accounts, inside the imported dates,
  /// that no incoming row matched. Reported, never deleted.
  required final List<BankTransaction> unmatchedEarlierImports,
});

/// Matches Empower rows against an account's existing rows so a re-import
/// adds only what is missing: same Empower id first, then the same amount
/// within [_sameTransactionWithinDays] days (exact day preferred).
class EmpowerTransactionsImport({
  required final Map<int, EmpowerAccountMapping> mappingByEmpowerAccountId,

  /// Null keeps contributions only.
  final Set<String>? transactionTypes,
}) {
  static const _sameTransactionWithinDays = 2;

  bool _includes(EmpowerTransaction row) =>
      mappingByEmpowerAccountId.containsKey(row.userAccountId) &&
      (transactionTypes?.contains(row.transactionType) ?? row.isContribution);

  EmpowerImportPlan plan({
    required List<EmpowerTransaction> incoming,
    required List<BankTransaction> existing,
    required int importedAtMillis,
  }) {
    final included = incoming.where(_includes).toList()
      ..sort(
        (left, right) => left.postedDay.sinceEpoch - right.postedDay.sinceEpoch,
      );
    final appAccountIds = {
      for (final mapping in mappingByEmpowerAccountId.values)
        mapping.appAccountId,
    };
    final onMappedAccounts = [
      for (final transaction in existing)
        if (appAccountIds.contains(transaction.accountId)) transaction,
    ];
    final existingExternalIds = {
      for (final transaction in onMappedAccounts) transaction.externalId,
    };
    final unclaimed = [
      for (final transaction in onMappedAccounts)
        if (!included.any((row) => row.externalId == transaction.externalId))
          transaction,
    ];

    final inserts = <BankTransaction>[];
    final externalIdByAdoptedTransactionId = <String, String>{};
    final recordedByOtherSource = <EmpowerTransaction>[];
    var alreadyImportedCount = 0;
    for (final row in included) {
      if (existingExternalIds.contains(row.externalId)) {
        alreadyImportedCount++;
        continue;
      }
      final mapping = mappingByEmpowerAccountId[row.userAccountId]!;
      final BankTransaction? sameTransaction = _claimSameTransaction(
        unclaimed: unclaimed,
        appAccountId: mapping.appAccountId,
        row: row,
      );
      if (sameTransaction == null) {
        inserts.add(_newTransaction(row, mapping, importedAtMillis));
      } else if (sameTransaction.isEmpowerImport) {
        externalIdByAdoptedTransactionId[sameTransaction.id] = row.externalId;
      } else {
        recordedByOtherSource.add(row);
      }
    }

    final CalendarDay? firstDay = included.firstOrNull?.postedDay;
    final CalendarDay? lastDay = included.lastOrNull?.postedDay;
    return EmpowerImportPlan(
      inserts: inserts,
      externalIdByAdoptedTransactionId: externalIdByAdoptedTransactionId,
      alreadyImportedCount: alreadyImportedCount,
      recordedByOtherSource: recordedByOtherSource,
      unmatchedEarlierImports: [
        if (firstDay != null && lastDay != null)
          for (final transaction in unclaimed)
            if (transaction.isEmpowerImport &&
                !transaction.postedDay.isBefore(firstDay) &&
                !transaction.postedDay.isAfter(lastDay))
              transaction,
      ],
    );
  }

  /// Removes and returns the best existing row for [row]: same account and
  /// amount, nearest day within the window, an earlier Empower import ahead
  /// of another source on a tie.
  static BankTransaction? _claimSameTransaction({
    required List<BankTransaction> unclaimed,
    required String appAccountId,
    required EmpowerTransaction row,
  }) {
    BankTransaction? best;
    var bestDistance = _sameTransactionWithinDays + 1;
    for (final candidate in unclaimed) {
      if (candidate.accountId != appAccountId ||
          candidate.amountCents != row.amountCents) {
        continue;
      }
      final int distance = candidate.postedDay.daysSince(row.postedDay).abs();
      if (distance > _sameTransactionWithinDays) continue;
      final bool closer = distance < bestDistance;
      final bool tieFavorsEarlierImport =
          distance == bestDistance &&
          candidate.isEmpowerImport &&
          !best!.isEmpowerImport;
      if (!closer && !tieFavorsEarlierImport) continue;
      best = candidate;
      bestDistance = distance;
    }
    if (best != null) unclaimed.remove(best);
    return best;
  }

  static BankTransaction _newTransaction(
    EmpowerTransaction row,
    EmpowerAccountMapping mapping,
    int importedAtMillis,
  ) {
    final description = '${mapping.label} · ${row.description}';
    return BankTransaction(
      id: const Uuid().v4(),
      accountId: mapping.appAccountId,
      externalId: row.externalId,
      postedAtMillis: row.postedDay.localMidnightMillis,
      amountCents: row.amountCents,
      rawDescription: description,
      normalizedMerchant: normalizeMerchant(description),
      pending: false,
      transactionType: row.transactionType,
      importedAtMillis: importedAtMillis,
    );
  }
}
