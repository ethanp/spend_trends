import 'package:spend_trends/domain/trends/centered_moving_average.dart';

/// One account or asset's daily balances, plus the first day it is known.
///
/// Days before [firstKnownDayIndex] are unavailable support, not zero-valued
/// samples. Smoothing runs only on the known suffix.
class NetWorthComponentHistory({
  required final List<double> rawDailyCents,
  required final int firstKnownDayIndex,
}) {
  List<double> get smoothedDailyCents {
    if (rawDailyCents.isEmpty) return const [];
    if (firstKnownDayIndex >= rawDailyCents.length) {
      return List<double>.filled(rawDailyCents.length, 0);
    }
    if (firstKnownDayIndex <= 0) {
      return CenteredMovingAverage.standard.smoothValues(rawDailyCents);
    }
    final knownSuffix = rawDailyCents.sublist(firstKnownDayIndex);
    final smoothedSuffix = CenteredMovingAverage.standard.smoothValues(
      knownSuffix,
    );
    return [...List<double>.filled(firstKnownDayIndex, 0), ...smoothedSuffix];
  }
}
