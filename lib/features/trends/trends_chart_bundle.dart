import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/conscious_spending_numbers.dart';

class const TrendsChartBundle({
  required final List<CategoryTrendSeries> categorySpend,
  required final List<CategoryTrendSeries> cashFlows,
  required final ConsciousSpendingNumbers consciousSpendingNumbers,
  final List<CategoryTrendSeries> netWorth = const [],
}) {
  bool get isEmpty =>
      categorySpend.isEmpty && cashFlows.isEmpty && netWorth.isEmpty;
}
