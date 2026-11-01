import 'dart:math' as math;
import 'dart:typed_data';

/// One day in a renormalized kernel support.
class const KernelWeightSample({
  required final int dayIndex,

  /// Normalized weight (samples at a center sum to 1).
  required final double weight,
});

/// Hann-tapered support for centered annualized pace.
///
/// Weights are 1 at the center and fall to 0 at ±[halfWidthDays], so large
/// deposits fade in/out instead of cliff-entering a hard box window.
///
/// The raw weights and their running sums are tabulated once per kernel, so a
/// pace at any center costs a handful of lookups instead of a thousand
/// cosines.
class HannAnnualPaceKernel({
  final int halfWidthDays = defaultHalfWidthDays,
  final int yearDays = defaultYearDays,
}) {
  /// ~36-month support (`2 * halfWidth + 1` ≈ 1095 days) so seasonal /
  /// bonus-scale lumps fade instead of drawing multi-month waves.
  static const defaultHalfWidthDays = 547;

  /// Annualize mean daily cents onto a year.
  static const defaultYearDays = 365;

  final _HannWeightTable _weightTable = _HannWeightTable(halfWidthDays);

  int get supportDays => 2 * halfWidthDays + 1;

  /// Raw Hann weight for offset from center; 0 outside the support.
  double rawWeight(int offsetDays) {
    final absOffset = offsetDays.abs();
    if (absOffset > halfWidthDays) return 0;
    return _weightTable.weightByOffset[absOffset];
  }

  /// Sum of raw weights over the support that fits inside the available
  /// history at [centerIndex]; 0 when the center is outside that history.
  double weightSumAt({
    required int centerIndex,
    required int historyStartIndex,
    required int lastDayIndex,
  }) {
    if (centerIndex < historyStartIndex || centerIndex > lastDayIndex) {
      return 0;
    }
    final offsetsBefore = math.min(
      halfWidthDays,
      centerIndex - historyStartIndex,
    );
    final offsetsAfter = math.min(halfWidthDays, lastDayIndex - centerIndex);
    return _weightTable.weightSumThroughOffset[offsetsBefore] +
        _weightTable.weightSumThroughOffset[offsetsAfter] -
        _weightTable.weightByOffset[0];
  }

  /// Share of the pace at [centerIndex] that one day at [dayIndex] carries,
  /// renormalized to the available history; 0 outside the support.
  double normalizedWeight({
    required int centerIndex,
    required int dayIndex,
    required int historyStartIndex,
    required int lastDayIndex,
  }) {
    if (dayIndex < historyStartIndex || dayIndex > lastDayIndex) return 0;
    final weightSum = weightSumAt(
      centerIndex: centerIndex,
      historyStartIndex: historyStartIndex,
      lastDayIndex: lastDayIndex,
    );
    if (weightSum <= 0) return 0;
    return rawWeight(dayIndex - centerIndex) / weightSum;
  }

  /// Weights over available history at [centerIndex], renormalized to sum to 1.
  List<KernelWeightSample> normalizedSamples({
    required int centerIndex,
    required int historyStartIndex,
    required int lastDayIndex,
  }) {
    final weightSum = weightSumAt(
      centerIndex: centerIndex,
      historyStartIndex: historyStartIndex,
      lastDayIndex: lastDayIndex,
    );
    if (weightSum <= 0) return const [];

    final firstIndex = math.max(historyStartIndex, centerIndex - halfWidthDays);
    final lastIndex = math.min(lastDayIndex, centerIndex + halfWidthDays);
    return [
      for (var dayIndex = firstIndex; dayIndex <= lastIndex; dayIndex++)
        if (rawWeight(dayIndex - centerIndex) > 0)
          KernelWeightSample(
            dayIndex: dayIndex,
            weight: rawWeight(dayIndex - centerIndex) / weightSum,
          ),
    ];
  }
}

/// Hann weights by |offset| and their running sums, for one half width.
class _HannWeightTable(final int halfWidthDays) {
  /// `weightByOffset[k]` is the raw weight `k` days from the center.
  final Float64List weightByOffset = _hannWeights(halfWidthDays);

  /// `weightSumThroughOffset[k]` is the sum of weights for offsets `0..k`.
  final Float64List weightSumThroughOffset = _runningSums(
    _hannWeights(halfWidthDays),
  );

  static Float64List _hannWeights(int halfWidthDays) {
    final weights = Float64List(halfWidthDays + 1);
    for (var offset = 0; offset <= halfWidthDays; offset++) {
      weights[offset] = halfWidthDays == 0
          ? 1
          : 0.5 * (1 + math.cos(math.pi * offset / halfWidthDays));
    }
    return weights;
  }

  static Float64List _runningSums(Float64List weights) {
    final sums = Float64List(weights.length);
    var runningSum = 0.0;
    for (var offset = 0; offset < weights.length; offset++) {
      runningSum += weights[offset];
      sums[offset] = runningSum;
    }
    return sums;
  }
}
