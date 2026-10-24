import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/build_trends_charts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

void main() {
  test('Trends emits group rollup plus member category series', () {
    final start = DateTime(2024, 1, 1);
    final transactions = [
      _txn(id: 'd0', day: start, categoryId: 'cat_dining', amountCents: -1000),
      _txn(id: 't0', day: start, categoryId: 'cat_travel', amountCents: -2000),
      _txn(id: 'h0', day: start, categoryId: 'cat_housing', amountCents: -5000),
      _txn(
        id: 'd1',
        day: start.add(const Duration(days: 1)),
        categoryId: 'cat_dining',
        amountCents: -1000,
      ),
      _txn(
        id: 't1',
        day: start.add(const Duration(days: 1)),
        categoryId: 'cat_travel',
        amountCents: -2000,
      ),
      _txn(
        id: 'h1',
        day: start.add(const Duration(days: 1)),
        categoryId: 'cat_housing',
        amountCents: -5000,
      ),
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: const [
        SpendCategory(
          id: 'cat_dining',
          name: 'Dining',
          sortOrder: 0,
          archived: false,
          groupId: 'grp_wants',
        ),
        SpendCategory(
          id: 'cat_travel',
          name: 'Travel',
          sortOrder: 1,
          archived: false,
          groupId: 'grp_wants',
        ),
        SpendCategory(
          id: 'cat_housing',
          name: 'Housing',
          sortOrder: 2,
          archived: false,
        ),
      ],
      groups: const [
        CategoryGroup(id: 'grp_wants', name: 'Wants', sortOrder: 0),
      ],
      endDate: start.add(const Duration(days: 1)),
    );

    final seriesIds = bundle.categorySpend.map((series) => series.id).toList();
    expect(seriesIds, contains(TrendChartCatalog.groupSeriesId('grp_wants')));
    expect(seriesIds, contains('cat_housing'));
    expect(seriesIds, contains('cat_dining'));
    expect(seriesIds, contains('cat_travel'));

    final wants = bundle.categorySpend.firstWhere(
      (series) => series.id == TrendChartCatalog.groupSeriesId('grp_wants'),
    );
    expect(wants.name, 'Wants');
    // Dining $10 + Travel $20 per day → $30/day → $10,950/yr annualized.
    expect(wants.points.last.rollingCents, closeTo(1095000, 0.01));

    final dining = bundle.categorySpend.firstWhere(
      (series) => series.id == 'cat_dining',
    );
    expect(dining.name, 'Dining');
    expect(
      dining.memberOfGroupSeriesId,
      TrendChartCatalog.groupSeriesId('grp_wants'),
    );
    // Group rollup is listed before its member lines.
    expect(
      seriesIds.indexOf(TrendChartCatalog.groupSeriesId('grp_wants')),
      lessThan(seriesIds.indexOf('cat_dining')),
    );
  });

  test('uncategorized series is only null-category spend', () {
    final start = DateTime(2024, 1, 1);
    final transactions = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++) ...[
        _txn(
          id: 'd$dayOffset',
          day: start.add(Duration(days: dayOffset)),
          categoryId: 'cat_dining',
          amountCents: -1000,
        ),
        _txn(
          id: 'o$dayOffset',
          day: start.add(Duration(days: dayOffset)),
          categoryId: 'cat_orphan',
          amountCents: -8000,
        ),
      ],
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: const [
        SpendCategory(
          id: 'cat_dining',
          name: 'Dining',
          sortOrder: 0,
          archived: false,
        ),
      ],
      endDate: start.add(const Duration(days: 9)),
    );

    expect(
      bundle.categorySpend.any(
        (series) => series.id == TrendChartCatalog.uncategorizedSeriesId,
      ),
      isFalse,
    );
    expect(
      bundle.categorySpend.any((series) => series.id == 'cat_dining'),
      isTrue,
    );
  });

  test('null-category spend still appears as uncategorized', () {
    final start = DateTime(2024, 1, 1);
    final transactions = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++)
        BankTransaction(
          id: 'u$dayOffset',
          accountId: 'a1',
          externalId: 'u$dayOffset',
          postedAt: start.add(Duration(days: dayOffset)),
          amountCents: -2500,
          rawDescription: 'Unknown',
          normalizedMerchant: 'UNKNOWN',
          pending: false,
        ),
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: const [],
      endDate: start.add(const Duration(days: 9)),
    );

    expect(
      bundle.categorySpend.any(
        (series) => series.id == TrendChartCatalog.uncategorizedSeriesId,
      ),
      isTrue,
    );
  });
}

BankTransaction _txn({
  required String id,
  required DateTime day,
  required String categoryId,
  required int amountCents,
}) {
  return BankTransaction(
    id: id,
    accountId: 'a1',
    externalId: id,
    postedAt: day,
    amountCents: amountCents,
    rawDescription: categoryId,
    normalizedMerchant: categoryId,
    pending: false,
    categoryId: categoryId,
  );
}
