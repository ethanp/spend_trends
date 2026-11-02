import 'package:spend_trends/domain/trends/category_trend_point.dart';
import 'package:spend_trends/domain/trends/hann_annual_pace_kernel.dart';

/// Min / median / mean / max / current from a series' smoothed trendline.
class const CategoryTrendDistribution({
  required final double minCents,
  required final double medianCents,
  required final double averageCents,
  required final double maxCents,
  required final double currentCents,
}) {
  @override
  bool operator ==(Object other) =>
      other is CategoryTrendDistribution &&
      other.minCents == minCents &&
      other.medianCents == medianCents &&
      other.averageCents == averageCents &&
      other.maxCents == maxCents &&
      other.currentCents == currentCents;

  @override
  int get hashCode =>
      Object.hash(minCents, medianCents, averageCents, maxCents, currentCents);

  CategoryTrendDistribution withCurrentCents(double currentCents) {
    return CategoryTrendDistribution(
      minCents: minCents,
      medianCents: medianCents,
      averageCents: averageCents,
      maxCents: maxCents,
      currentCents: currentCents,
    );
  }
}

/// All-time and recent-year distributions for one series.
class const CategoryTrendDistributionPair({
  required final CategoryTrendDistribution? allTime,
  required final CategoryTrendDistribution? pastYear,
}) {
  bool get isEmpty => allTime == null && pastYear == null;

  CategoryTrendDistributionPair withCurrentCents(double currentCents) {
    return CategoryTrendDistributionPair(
      allTime: allTime?.withCurrentCents(currentCents),
      pastYear: pastYear?.withCurrentCents(currentCents),
    );
  }
}

/// Stats over smoothed values, skipping leading non-positive samples.
///
/// When [onOrAfter] is set, only points on/after that day are sampled.
/// Returns null when there are no positive smoothed samples in range.
CategoryTrendDistribution? distributionForSmoothed(
  List<CategoryTrendPoint> points, {
  DateTime? onOrAfter,
}) {
  if (points.isEmpty) return null;

  var firstPositiveIndex = 0;
  while (firstPositiveIndex < points.length &&
      points[firstPositiveIndex].smoothedCents <= 0) {
    firstPositiveIndex++;
  }
  if (firstPositiveIndex >= points.length) return null;

  final sampleCents = <double>[];
  for (var index = firstPositiveIndex; index < points.length; index++) {
    final point = points[index];
    if (onOrAfter != null && point.date.isBefore(onOrAfter)) continue;
    sampleCents.add(point.smoothedCents);
  }
  if (sampleCents.isEmpty) return null;

  var minCents = sampleCents.first;
  var maxCents = sampleCents.first;
  var sumCents = 0.0;
  for (final cents in sampleCents) {
    if (cents < minCents) minCents = cents;
    if (cents > maxCents) maxCents = cents;
    sumCents += cents;
  }

  final sortedCents = [...sampleCents]..sort();
  return CategoryTrendDistribution(
    minCents: minCents,
    medianCents: _median(sortedCents),
    averageCents: sumCents / sampleCents.length,
    maxCents: maxCents,
    currentCents: points.last.smoothedCents,
  );
}

/// All-time plus the last [HannAnnualPaceKernel.defaultYearDays] of points.
CategoryTrendDistributionPair distributionPairForSmoothed(
  List<CategoryTrendPoint> points,
) {
  if (points.isEmpty) {
    return const CategoryTrendDistributionPair(allTime: null, pastYear: null);
  }
  final pastYearStart = points.last.date.subtract(
    const Duration(days: HannAnnualPaceKernel.defaultYearDays),
  );
  return CategoryTrendDistributionPair(
    allTime: distributionForSmoothed(points),
    pastYear: distributionForSmoothed(points, onOrAfter: pastYearStart),
  );
}

double _median(List<double> sortedAscending) {
  final midpoint = sortedAscending.length ~/ 2;
  if (sortedAscending.length.isOdd) {
    return sortedAscending[midpoint];
  }
  return (sortedAscending[midpoint - 1] + sortedAscending[midpoint]) / 2;
}
