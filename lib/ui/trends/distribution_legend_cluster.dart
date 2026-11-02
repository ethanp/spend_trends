import 'package:spend_trends/ui/trends/category_trend_series.dart';

/// Group rollup (or standalone category) plus its member series for whiskers.
class const DistributionLegendCluster({
  required final CategoryTrendSeries rollup,
  final List<CategoryTrendSeries> members = const [],
}) {
  bool get canExpand => members.isNotEmpty;

  static List<DistributionLegendCluster> fromSeries(
    List<CategoryTrendSeries> seriesList,
  ) {
    final membersByGroupSeriesId = <String, List<CategoryTrendSeries>>{};
    final rollups = <CategoryTrendSeries>[];
    for (final series in seriesList) {
      final groupSeriesId = series.memberOfGroupSeriesId;
      if (groupSeriesId == null) {
        rollups.add(series);
        continue;
      }
      membersByGroupSeriesId.putIfAbsent(groupSeriesId, () => []).add(series);
    }
    return [
      for (final rollup in rollups)
        DistributionLegendCluster(
          rollup: rollup,
          members: membersByGroupSeriesId[rollup.id] ?? const [],
        ),
    ];
  }
}
