import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/features/trends/category_trend_point.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/distribution_legend_cluster.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

void main() {
  test(
    'rolls member series under their group and leaves standalones rolled up',
    () {
      final wants = _series(id: 'group:wants', name: 'Wants');
      final dining = _series(
        id: 'cat_dining',
        name: 'Dining',
        memberOfGroupSeriesId: 'group:wants',
      );
      final travel = _series(
        id: 'cat_travel',
        name: 'Travel',
        memberOfGroupSeriesId: 'group:wants',
      );
      final housing = _series(id: 'cat_housing', name: 'Housing');

      final clusters = DistributionLegendCluster.fromSeries([
        wants,
        dining,
        travel,
        housing,
      ]);

      expect(clusters, hasLength(2));
      expect(clusters.first.rollup.id, 'group:wants');
      expect(clusters.first.canExpand, isTrue);
      expect(clusters.first.members.map((series) => series.id), [
        'cat_dining',
        'cat_travel',
      ]);
      expect(clusters.last.rollup.id, 'cat_housing');
      expect(clusters.last.canExpand, isFalse);
    },
  );

  test('left legend is totals and guides, not Other', () {
    expect(
      _series(
        id: TrendChartCatalog.allSpendSeriesId,
        name: 'All spending',
      ).isMetaLegend,
      isTrue,
    );
    expect(
      _series(
        id: TrendChartCatalog.housingAffordabilitySeriesId,
        name: '30% of income',
      ).isMetaLegend,
      isTrue,
    );
    expect(
      _series(
        id: TrendChartCatalog.uncategorizedSeriesId,
        name: 'Uncategorized',
      ).isMetaLegend,
      isTrue,
    );
    expect(_series(id: 'cat_other', name: 'Other').isMetaLegend, isFalse);
    expect(_series(id: 'cat_housing', name: 'Housing').isMetaLegend, isFalse);
  });
}

CategoryTrendSeries _series({
  required String id,
  required String name,
  String? memberOfGroupSeriesId,
}) {
  return CategoryTrendSeries(
    id: id,
    name: name,
    lineColor: const Color(0xFF00AA00),
    memberOfGroupSeriesId: memberOfGroupSeriesId,
    points: [
      CategoryTrendPoint(
        date: DateTime(2024, 1, 1),
        rollingCents: 100,
        smoothedCents: 100,
      ),
    ],
  );
}
