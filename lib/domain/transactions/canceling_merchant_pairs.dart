import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';

/// Brokerage / bank ledger noise: equal and opposite amounts in the same account.
///
/// - Non-investment: same local day + same merchant (e.g. dividend reinvest).
/// - Investment (IRA / brokerage): merchant ignored; amounts may settle across
///   a few calendar days (sell MM on Friday, buy fund on Monday).
class CancelingMerchantPairs._() {
  /// Max calendar-day gap for investment fund-swap pairing.
  static const investmentPairMaxCalendarDays = 7;

  /// Transaction ids that form canceling pairs (both sides of each pair).
  static Set<String> transactionIds(
    Iterable<BankTransaction> transactions, {
    Set<String> investmentAccountIds = const {},
  }) {
    final nonInvestmentBuckets = <String, _AmountBucket>{};
    final investmentBuckets = <String, _AmountBucket>{};

    for (final transaction in transactions) {
      if (transaction.isZeroAmount) continue;
      final isInvestment = investmentAccountIds.contains(transaction.accountId);
      if (!isInvestment && transaction.normalizedMerchant.isEmpty) continue;
      final key = _groupKey(transaction, isInvestment: isInvestment);
      final buckets = isInvestment ? investmentBuckets : nonInvestmentBuckets;
      buckets.putIfAbsent(key, _AmountBucket.new).add(transaction);
    }

    final cancelingIds = <String>{};
    for (final bucket in nonInvestmentBuckets.values) {
      cancelingIds.addAll(bucket.pairedIdsSameDay());
    }
    for (final bucket in investmentBuckets.values) {
      cancelingIds.addAll(
        bucket.pairedIdsWithinCalendarDays(investmentPairMaxCalendarDays),
      );
    }
    return cancelingIds;
  }

  static List<BankTransaction> excludingCancelingPairs(
    List<BankTransaction> transactions, {
    Set<String> investmentAccountIds = const {},
    Map<String, Account>? accountsById,
  }) {
    final investmentIds = investmentAccountIds.isNotEmpty
        ? investmentAccountIds
        : investmentIdsFrom(accountsById);
    final cancelingIds = transactionIds(
      transactions,
      investmentAccountIds: investmentIds,
    );
    if (cancelingIds.isEmpty) return transactions;
    return [
      for (final transaction in transactions)
        if (!cancelingIds.contains(transaction.id)) transaction,
    ];
  }

  static Set<String> investmentIdsFrom(Map<String, Account>? accountsById) {
    if (accountsById == null || accountsById.isEmpty) return const {};
    return {
      for (final account in accountsById.values)
        if (account.isInvestment) account.id,
    };
  }

  static String _groupKey(
    BankTransaction transaction, {
    required bool isInvestment,
  }) {
    final absAmount = transaction.amountCents.abs();
    if (isInvestment) {
      return '${transaction.accountId}|$absAmount';
    }
    return '${transaction.accountId}|${transaction.postedDay.isoDate}|'
        '${transaction.normalizedMerchant}|$absAmount';
  }
}

class _AmountBucket() {
  final List<BankTransaction> inflows = [];
  final List<BankTransaction> outflows = [];

  void add(BankTransaction transaction) {
    if (transaction.amountCents > 0) {
      inflows.add(transaction);
    } else {
      outflows.add(transaction);
    }
  }

  /// Same-day buckets: pair greedily by list order.
  Iterable<String> pairedIdsSameDay() sync* {
    final pairCount = inflows.length < outflows.length
        ? inflows.length
        : outflows.length;
    for (var index = 0; index < pairCount; index++) {
      yield inflows[index].id;
      yield outflows[index].id;
    }
  }

  /// Investment buckets: pair each inflow to the nearest unmatched outflow
  /// within [maxCalendarDays].
  Iterable<String> pairedIdsWithinCalendarDays(int maxCalendarDays) sync* {
    final unmatchedOutflows = List<BankTransaction>.from(outflows);
    for (final inflow in inflows) {
      BankTransaction? bestOutflow;
      var bestDayDiff = maxCalendarDays + 1;
      for (final outflow in unmatchedOutflows) {
        final int dayDiff = inflow.postedDay.daysSince(outflow.postedDay).abs();
        if (dayDiff > maxCalendarDays) continue;
        if (dayDiff < bestDayDiff) {
          bestDayDiff = dayDiff;
          bestOutflow = outflow;
        }
      }
      if (bestOutflow == null) continue;
      unmatchedOutflows.remove(bestOutflow);
      yield inflow.id;
      yield bestOutflow.id;
    }
  }
}
