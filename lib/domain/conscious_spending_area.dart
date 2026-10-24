import 'package:ethan_utils/ethan_utils.dart';

/// Ramit Sethi's four conscious-spending buckets (share of take-home pay).
enum ConsciousSpendingArea({
  required final int minPercent,
  required final int maxPercent,
  final String? _displayName,
  final String? _chartSeriesName,
}) {
  fixedCosts(minPercent: 50, maxPercent: 60),
  investments(minPercent: 10, maxPercent: 10),
  savings(minPercent: 5, maxPercent: 10, chartSeriesName: 'Savings goals'),
  guiltFree(minPercent: 20, maxPercent: 35, displayName: 'Guilt-free');

  String get displayName => _displayName ?? nameAsCapitalizedWords;

  String get chartSeriesName => _chartSeriesName ?? displayName;

  String get storageValue => name;

  /// Guideline share of take-home pay, e.g. `50–60%` or `10%`.
  String get targetRangeLabel => minPercent == maxPercent
      ? '$minPercent%'
      : '$minPercent–$maxPercent%';

  bool containsPercent(int percent) =>
      percent >= minPercent && percent <= maxPercent;

  /// Rounded share of [incomeCents], or null when there is no take-home pay.
  int? percentOfIncome({required int areaCents, required int incomeCents}) {
    if (incomeCents <= 0) return null;
    return (areaCents / incomeCents * 100).round();
  }

  /// Guideline percents applied to annual take-home [incomeCents].
  String impliedTakeHomeLabel(int incomeCents) {
    if (incomeCents <= 0) return '—';
    final lowCents = (incomeCents * minPercent / 100).round();
    final highCents = (incomeCents * maxPercent / 100).round();
    final lowLabel = formatCentsWholeDollars(lowCents);
    if (lowCents == highCents) return lowLabel;
    return '$lowLabel–${formatCentsWholeDollars(highCents)}';
  }

  static ConsciousSpendingArea? fromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final area in values) {
      if (area.name == value) return area;
    }
    return null;
  }
}
