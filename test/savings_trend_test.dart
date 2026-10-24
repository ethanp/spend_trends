import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/build_trends_charts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

void main() {
  test('cash-flow chart includes savings as income minus spending', () {
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
          id: 'spend$dayOffset',
          accountId: 'a1',
          externalId: 's$dayOffset',
          postedAt: start.add(Duration(days: dayOffset)),
          amountCents: -4000,
          rawDescription: 'Shop',
          normalizedMerchant: 'SHOP',
          pending: false,
          categoryId: 'cat_dining',
        ),
      ],
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: [SpecialCategory.income.asSpendCategory()],
      endDate: end,
    );

    final income = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.incomeSeriesId,
    );
    final spending = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.spendingSeriesId,
    );
    final savings = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.savingsSeriesId,
    );

    final fireGuide = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.fireSavingsGuideSeriesId,
    );

    expect(savings.name, 'Savings');
    expect(savings.legendCaption, 'Income − Spending');
    expect(fireGuide.name, '25% of income');
    expect(fireGuide.legendCaption, 'FIRE guide');
    expect(fireGuide.guide, isTrue);
    expect(savings.points.length, income.points.length);
    for (var pointIndex = 0; pointIndex < income.points.length; pointIndex++) {
      expect(
        savings.points[pointIndex].rollingCents,
        closeTo(
          income.points[pointIndex].rollingCents -
              spending.points[pointIndex].rollingCents,
          0.01,
        ),
      );
      expect(
        fireGuide.points[pointIndex].rollingCents,
        closeTo(
          income.points[pointIndex].rollingCents *
              TrendChartCatalog.fireSavingsIncomeShare,
          0.01,
        ),
      );
    }
  });
}
