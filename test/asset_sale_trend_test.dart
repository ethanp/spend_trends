import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/build_trends_charts.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

void main() {
  final start = DateTime(2024, 1, 1);
  final saleDay = start.add(const Duration(days: 5));
  final end = start.add(const Duration(days: 9));

  BankTransaction paycheck(int dayOffset) => BankTransaction(
    id: 'pay$dayOffset',
    accountId: 'checking',
    externalId: 'p$dayOffset',
    postedAt: start.add(Duration(days: dayOffset)),
    amountCents: 10000,
    rawDescription: 'Pay',
    normalizedMerchant: 'PAY',
    pending: false,
    categoryId: SpecialCategory.income.id,
  );

  final mortgagePayoff = BankTransaction(
    id: 'payoff',
    accountId: 'mortgage',
    externalId: 'payoff',
    postedAt: saleDay,
    amountCents: 36162500,
    rawDescription: 'Payoff, Wire-bwr',
    normalizedMerchant: 'PAYOFF WIRE',
    pending: false,
    categoryId: SpecialCategory.assetSale.id,
  );

  final transactions = [
    for (var dayOffset = 0; dayOffset < 10; dayOffset++) paycheck(dayOffset),
    mortgagePayoff,
  ];

  final bundle = const BuildTrendsCharts().build(
    transactions: transactions,
    categories: [
      SpecialCategory.income.asSpendCategory(),
      SpecialCategory.assetSale.asSpendCategory(),
    ],
    accounts: const [
      Account(
        id: 'checking',
        externalId: 'checking',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 100000,
        status: AccountStatus.ok,
      ),
      Account(
        id: 'mortgage',
        externalId: 'mortgage',
        name: 'Mortgage',
        currency: 'USD',
        balanceCents: 0,
        status: AccountStatus.ok,
      ),
    ],
    endDate: end,
  );

  test('asset sale proceeds stay out of income and spending', () {
    final income = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.incomeSeriesId,
    );
    expect(income.points.last.rollingCents, lessThan(36162500));
    expect(
      bundle.cashFlows.any(
        (series) => series.id == TrendChartCatalog.transferSeriesId,
      ),
      isFalse,
    );
    expect(
      bundle.categorySpend.any(
        (series) => series.id == SpecialCategory.assetSale.id,
      ),
      isFalse,
    );
  });

  test('net worth plots asset sales as a cumulative lump-sum step', () {
    final assetSales = bundle.netWorth.firstWhere(
      (series) => series.id == TrendChartCatalog.assetSalesSeriesId,
    );
    final beforeSale = assetSales.points.firstWhere(
      (point) => point.date == saleDay.subtract(const Duration(days: 1)),
    );
    final onSale = assetSales.points.firstWhere(
      (point) => point.date == saleDay,
    );
    expect(beforeSale.smoothedCents, 0);
    expect(onSale.smoothedCents, 36162500);
    expect(assetSales.points.last.smoothedCents, 36162500);
    expect(assetSales.isMetaLegend, isTrue);
  });

  test('asset sale is a locked flow built-in, not income', () {
    final assetSale = SpecialCategory.assetSale.asSpendCategory();
    expect(assetSale.isFlow, isTrue);
    expect(assetSale.isIncome, isFalse);
    expect(assetSale.lockedCaption, isNotNull);
    expect(SpecialCategory.investments.asSpendCategory().lockedCaption, isNull);
    expect(SpecialCategory.isReservedName('Asset sale'), isTrue);
  });
}
