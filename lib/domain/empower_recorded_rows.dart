import 'package:spend_trends/domain/transaction.dart';

/// Rows an Empower import recorded on an account that the live bank feed
/// has not, so the feed's copy of one of them is skipped instead of counted
/// twice. Matching is per row (same amount within [_sameRowWithinDays]
/// days), so two real contributions on one payday stay two rows.
class EmpowerRecordedRows._(final List<BankTransaction> _unclaimed) {
  static const _sameRowWithinDays = 2;

  /// From every row on one account: Empower rows the feed already has a
  /// row for are set aside first, nearest day first.
  factory forAccount(List<BankTransaction> accountRows) {
    final unclaimed = [
      for (final row in accountRows)
        if (row.isEmpowerImport) row,
    ];
    final recordedRows = EmpowerRecordedRows._(unclaimed);
    for (final row in accountRows) {
      if (!row.isEmpowerImport) recordedRows.claim(row);
    }
    return recordedRows;
  }

  /// Takes the Empower row that records [feedRow], if one is left.
  bool claim(BankTransaction feedRow) {
    BankTransaction? nearest;
    var nearestDistance = _sameRowWithinDays + 1;
    for (final row in _unclaimed) {
      if (row.amountCents != feedRow.amountCents) continue;
      final int distance = row.postedDay.daysSince(feedRow.postedDay).abs();
      if (distance >= nearestDistance) continue;
      nearest = row;
      nearestDistance = distance;
    }
    if (nearest == null) return false;
    _unclaimed.remove(nearest);
    return true;
  }
}
