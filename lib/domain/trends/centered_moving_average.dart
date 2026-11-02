import 'package:spend_trends/domain/trends/category_trend_point.dart';
import 'package:ethan_utils/ethan_utils.dart';

/// Simple centered moving-average smoother (level series like net worth).
class const CenteredMovingAverage({
  final int halfWindowDays = 21,
  final int passCount = 3,
}) {
  static const standard = CenteredMovingAverage();

  List<CategoryTrendPoint> smoothPoints(List<CategoryTrendPoint> rawPoints) {
    final smoothedValues = smoothValues(
      rawPoints.mapL((point) => point.rollingCents),
    );
    return rawPoints.mapLWithIndex(
      (rawPoint, pointIndex) => CategoryTrendPoint(
        date: rawPoint.date,
        rollingCents: rawPoint.rollingCents,
        smoothedCents: smoothedValues[pointIndex],
      ),
    );
  }

  List<double> smoothValues(List<double> values) {
    var smoothedValues = values;
    for (var pass = 0; pass < passCount; pass++) {
      smoothedValues = smooth(smoothedValues);
    }
    return smoothedValues;
  }

  /// Full width shifts inward at tips so every output uses [2*half+1] samples
  /// when the series is long enough.
  List<double> smooth(List<double> values) {
    if (values.isEmpty) return const [];
    final lastIndex = values.length - 1;
    final fullSpan = 2 * halfWindowDays + 1;
    final prefixSums = List<double>.filled(values.length + 1, 0);
    for (var index = 0; index < values.length; index++) {
      prefixSums[index + 1] = prefixSums[index] + values[index];
    }
    return List.generate(values.length, (index) {
      if (values.length < fullSpan) {
        return prefixSums[values.length] / values.length;
      }
      var firstIndex = index - halfWindowDays;
      var lastWindowIndex = index + halfWindowDays;
      if (firstIndex < 0) {
        firstIndex = 0;
        lastWindowIndex = fullSpan - 1;
      } else if (lastWindowIndex > lastIndex) {
        lastWindowIndex = lastIndex;
        firstIndex = lastWindowIndex - fullSpan + 1;
      }
      return (prefixSums[lastWindowIndex + 1] - prefixSums[firstIndex]) /
          (lastWindowIndex - firstIndex + 1);
    });
  }
}
