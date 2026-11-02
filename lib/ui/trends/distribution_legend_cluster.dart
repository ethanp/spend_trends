import 'package:spend_trends/ui/trends/category_trend_series.dart';
import 'package:ethan_utils/ethan_utils.dart';

/// Spending-area rollup (or standalone category) plus its member series for whiskers.
class const DistributionLegendCluster({
  required final CategoryTrendSeries rollup,
  final List<CategoryTrendSeries> members = const [],
}) {
  bool get canExpand => members.isNotEmpty;

  static List<DistributionLegendCluster> fromSeries(
    List<CategoryTrendSeries> seriesList,
  ) {
    final membersByRollupSeriesId = <String, List<CategoryTrendSeries>>{};
    final rollups = <CategoryTrendSeries>[];
    for (final series in seriesList) {
      final rollupSeriesId = series.memberOfRollupSeriesId;
      if (rollupSeriesId == null) {
        rollups.add(series);
        continue;
      }
      membersByRollupSeriesId.putIfAbsent(rollupSeriesId, () => []).add(series);
    }
    return rollups.mapL(
      (rollup) => DistributionLegendCluster(
        rollup: rollup,
        members: membersByRollupSeriesId[rollup.id] ?? const [],
      ),
    );
  }
}
