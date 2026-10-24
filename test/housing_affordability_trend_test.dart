import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/build_trends_charts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

void main() {
  test('category spend includes 30% of income affordability boundary', () {
    final start = DateTime(2024, 1, 1);
    final end = start.add(const Duration(days: 9));
    final transactions = <BankTransaction>[
      for (var dayOffset = 0; dayOffset < 10; dayOffset++) ...[
        BankTransaction(
          id: 'income$dayOffset',
          accountId: 'a1',
          externalId: 'i$dayOffset',
          postedAt: start.add(Duration(days: dayOffset)),
          amountCents: 10000,
          rawDescription: 'Pay',
          normalizedMerchant: 'PAY',
          pending: false,
          categoryId: SpecialCategory.income.id,
        ),
        BankTransaction(
          id: 'housing$dayOffset',
          accountId: 'a1',
          externalId: 'h$dayOffset',
          postedAt: start.add(Duration(days: dayOffset)),
          amountCents: -2000,
          rawDescription: 'Rent',
          normalizedMerchant: 'RENT',
          pending: false,
          categoryId: SpecialCategory.housing.id,
        ),
      ],
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: [
        SpecialCategory.housing.asSpendCategory(),
        SpecialCategory.income.asSpendCategory(),
      ],
      endDate: end,
    );

    final allSpending = bundle.categorySpend.firstWhere(
      (series) => series.id == TrendChartCatalog.allSpendSeriesId,
    );
    expect(allSpending.name, 'All spending');
    expect(allSpending.dotted, isTrue);

    final affordability = bundle.categorySpend.firstWhere(
      (series) => series.id == TrendChartCatalog.housingAffordabilitySeriesId,
    );
    final income = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.incomeSeriesId,
    );

    expect(affordability.guide, isTrue);
    expect(affordability.dotted, isFalse);
    expect(affordability.name, '30% of income');
    expect(affordability.points.length, income.points.length);
    for (var pointIndex = 0; pointIndex < income.points.length; pointIndex++) {
      expect(
        affordability.points[pointIndex].rollingCents,
        closeTo(
          income.points[pointIndex].rollingCents *
              TrendChartCatalog.housingIncomeShareCap,
          0.01,
        ),
      );
    }
  });
}
