import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/build_trends_charts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

void main() {
  test('Investments fills the investments area, not income or spend', () {
    final start = DateTime(2024, 1, 1);
    final end = start.add(const Duration(days: 9));
    final transactions = <BankTransaction>[
      for (var dayOffset = 0; dayOffset < 10; dayOffset++) ...[
        BankTransaction(
          id: 'income$dayOffset',
          accountId: 'a1',
          externalId: 'i$dayOffset',
          postedAtMillis: start
              .add(Duration(days: dayOffset))
              .millisecondsSinceEpoch,
          amountCents: 5000,
          rawDescription: 'Pay',
          normalizedMerchant: 'PAY',
          pending: false,
          categoryId: SpecialCategory.income.id,
        ),
        BankTransaction(
          id: 'invest$dayOffset',
          accountId: 'a1',
          externalId: 'v$dayOffset',
          postedAtMillis: start
              .add(Duration(days: dayOffset))
              .millisecondsSinceEpoch,
          amountCents: -2000,
          rawDescription: 'Brokerage deposit',
          normalizedMerchant: 'BROKERAGE DEPOSIT',
          pending: false,
          categoryId: SpecialCategory.investments.id,
        ),
        BankTransaction(
          id: 'spend$dayOffset',
          accountId: 'a1',
          externalId: 's$dayOffset',
          postedAtMillis: start
              .add(Duration(days: dayOffset))
              .millisecondsSinceEpoch,
          amountCents: -1000,
          rawDescription: 'Shop',
          normalizedMerchant: 'SHOP',
          pending: false,
          categoryId: 'cat_dining',
        ),
      ],
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: [
        SpecialCategory.income.asSpendCategory(),
        SpecialCategory.investments.asSpendCategory(),
        const SpendCategory(
          id: 'cat_dining',
          name: 'Dining',
          sortOrder: 0,
          archived: false,
        ),
      ],
      endDate: end,
    );

    expect(
      bundle.categorySpend.any(
        (series) => series.id == SpecialCategory.investments.id,
      ),
      isFalse,
    );

    final income = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.incomeSeriesId,
    );
    final spending = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.spendingSeriesId,
    );
    final investmentsArea = bundle.cashFlows.firstWhere(
      (series) =>
          series.id ==
          TrendChartCatalog.consciousSpendingAreaSeriesId(
            ConsciousSpendingArea.investments,
          ),
    );
    expect(income.points.last.rollingCents, closeTo(1825000, 0.01));
    expect(spending.points.last.rollingCents, closeTo(365000, 0.01));
    expect(investmentsArea.points.last.rollingCents, closeTo(730000, 0.01));
  });

  test('assigned conscious-spending areas build cash-flow series without changing Income or Spending', () {
    final start = DateTime(2024, 1, 1);
    final end = start.add(const Duration(days: 9));
    final transactions = <BankTransaction>[
      for (var dayOffset = 0; dayOffset < 10; dayOffset++) ...[
        BankTransaction(
          id: 'income$dayOffset',
          accountId: 'a1',
          externalId: 'i$dayOffset',
          postedAtMillis: start
              .add(Duration(days: dayOffset))
              .millisecondsSinceEpoch,
          amountCents: 10000,
          rawDescription: 'Pay',
          normalizedMerchant: 'PAY',
          pending: false,
          categoryId: SpecialCategory.income.id,
        ),
        BankTransaction(
          id: 'rent$dayOffset',
          accountId: 'a1',
          externalId: 'r$dayOffset',
          postedAtMillis: start
              .add(Duration(days: dayOffset))
              .millisecondsSinceEpoch,
          amountCents: -5000,
          rawDescription: 'Rent',
          normalizedMerchant: 'RENT',
          pending: false,
          categoryId: SpecialCategory.housing.id,
        ),
        BankTransaction(
          id: 'dining$dayOffset',
          accountId: 'a1',
          externalId: 'd$dayOffset',
          postedAtMillis: start
              .add(Duration(days: dayOffset))
              .millisecondsSinceEpoch,
          amountCents: -2000,
          rawDescription: 'Tacos',
          normalizedMerchant: 'TACOS',
          pending: false,
          categoryId: 'cat_dining',
        ),
      ],
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: [
        SpecialCategory.income.asSpendCategory(),
        SpecialCategory.housing.asSpendCategory(),
        const SpendCategory(
          id: 'cat_dining',
          name: 'Dining',
          sortOrder: 0,
          archived: false,
          consciousSpendingArea: ConsciousSpendingArea.guiltFree,
        ),
      ],
      endDate: end,
    );

    final income = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.incomeSeriesId,
    );
    final spending = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.spendingSeriesId,
    );
    final fixedCosts = bundle.cashFlows.firstWhere(
      (series) =>
          series.id ==
          TrendChartCatalog.consciousSpendingAreaSeriesId(
            ConsciousSpendingArea.fixedCosts,
          ),
    );
    final guiltFree = bundle.cashFlows.firstWhere(
      (series) =>
          series.id ==
          TrendChartCatalog.consciousSpendingAreaSeriesId(
            ConsciousSpendingArea.guiltFree,
          ),
    );

    expect(income.points.last.rollingCents, closeTo(3650000, 0.01));
    expect(spending.points.last.rollingCents, closeTo(2555000, 0.01));
    expect(fixedCosts.points.last.rollingCents, closeTo(1825000, 0.01));
    expect(guiltFree.points.last.rollingCents, closeTo(730000, 0.01));
    expect(fixedCosts.legendCaption, isNull);
    expect(guiltFree.legendCaption, isNull);
    expect(
      ConsciousSpendingArea.fixedCosts.ramitGuideline.impliedCents(3650000),
      2007500,
    );
    expect(
      ConsciousSpendingArea.investments.ramitGuideline.impliedCents(3650000),
      365000,
    );
    expect(ConsciousSpendingArea.fixedCosts.ramitGuideline.isMetBy(50), isTrue);
    expect(
      ConsciousSpendingArea.fixedCosts.ramitGuideline.isMetBy(56),
      isFalse,
    );
  });
}
