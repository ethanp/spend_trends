import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/build_trends_charts.dart';
import 'package:spend_trends/features/trends/trend_point_contributors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

void main() {
  test(
    'top contributors rank by smoothed contribution for a category series',
    () {
      final chartStart = DateTime(2024, 1, 1);
      final spikeDay = DateTime(2024, 6, 15);
      final chartEnd = DateTime(2024, 6, 30);

      final spikeSpecs = <({String id, int amountCents, String merchant})>[
        (id: 'big', amountCents: -10000, merchant: 'BIG'),
        (id: 'mid', amountCents: -5000, merchant: 'MID'),
        (id: 'med', amountCents: -3000, merchant: 'MED'),
        (id: 'small', amountCents: -2000, merchant: 'SMALL'),
        (id: 'tiny', amountCents: -1000, merchant: 'TINY'),
        (id: 'noise', amountCents: -400, merchant: 'NOISE'),
      ];

      final transactions = <BankTransaction>[
        BankTransaction(
          id: 'seed',
          accountId: 'a1',
          externalId: 'seed',
          postedAt: chartStart,
          amountCents: -100,
          rawDescription: 'Seed',
          normalizedMerchant: 'SEED',
          pending: false,
          categoryId: 'cat_dining',
        ),
        for (final spike in spikeSpecs)
          BankTransaction(
            id: spike.id,
            accountId: 'a1',
            externalId: spike.id,
            postedAt: spikeDay,
            amountCents: spike.amountCents,
            rawDescription: spike.merchant,
            normalizedMerchant: spike.merchant,
            pending: false,
            categoryId: 'cat_dining',
          ),
      ];

      const dining = SpendCategory(
        id: 'cat_dining',
        name: 'Dining',
        sortOrder: 0,
        archived: false,
      );

      final bundle = const BuildTrendsCharts().build(
        transactions: transactions,
        categories: const [dining],
        endDate: chartEnd,
      );
      final diningSeries = bundle.categorySpend.firstWhere(
        (series) => series.id == 'cat_dining',
      );

      final topContributors = TrendPointContributors.topForSeries(
        series: diningSeries,
        tapDate: spikeDay,
        transactions: transactions,
        categories: const [dining],
        groups: const [],
      );

      expect(topContributors, hasLength(5));
      expect(
        [
          for (final contributor in topContributors)
            contributor.transaction.normalizedMerchant,
        ],
        ['BIG', 'MID', 'MED', 'SMALL', 'TINY'],
      );
      expect(topContributors.first.rawAmountCents, -10000);
      for (var index = 0; index < topContributors.length - 1; index++) {
        expect(
          topContributors[index].smoothedContributionCents.abs(),
          greaterThan(
            topContributors[index + 1].smoothedContributionCents.abs(),
          ),
        );
      }

      // Same-day spikes share the time kernel; contribution scales with spend.
      final bigOverMid =
          topContributors[0].smoothedContributionCents /
          topContributors[1].smoothedContributionCents;
      expect(bigOverMid, closeTo(2.0, 0.01));

      // Linearity: all member contributions sum to the series smoothed value.
      final allContributors = TrendPointContributors.topForSeries(
        series: diningSeries,
        tapDate: spikeDay,
        transactions: transactions,
        categories: const [dining],
        groups: const [],
        limit: 100,
      );
      final contributionSum = allContributors.fold<double>(
        0,
        (sum, contributor) => sum + contributor.smoothedContributionCents,
      );
      final tapPoint = diningSeries.points.firstWhere(
        (point) =>
            point.date.year == spikeDay.year &&
            point.date.month == spikeDay.month &&
            point.date.day == spikeDay.day,
      );
      expect(contributionSum, closeTo(tapPoint.smoothedCents, 1.0));

      // Hann kernel: same-day impulse is a positive share of annualized pace.
      expect(
        topContributors.first.smoothedContributionCents,
        greaterThan(1000),
      );
      expect(
        topContributors.first.smoothedContributionCents,
        lessThan(10000.0 * 365),
      );
    },
  );

  test('category inflow ranks by abs contribution as negative spend', () {
    final start = DateTime(2024, 1, 1);
    final refundDay = DateTime(2024, 6, 15);
    final end = DateTime(2024, 6, 30);
    final transactions = <BankTransaction>[
      BankTransaction(
        id: 'seed',
        accountId: 'a1',
        externalId: 'seed',
        postedAt: start,
        amountCents: -100,
        rawDescription: 'Seed',
        normalizedMerchant: 'SEED',
        pending: false,
        categoryId: 'cat_housing',
      ),
      BankTransaction(
        id: 'rent',
        accountId: 'a1',
        externalId: 'rent',
        postedAt: refundDay,
        amountCents: -200000,
        rawDescription: 'Rent',
        normalizedMerchant: 'RENT',
        pending: false,
        categoryId: 'cat_housing',
      ),
      BankTransaction(
        id: 'earnest',
        accountId: 'a1',
        externalId: 'earnest',
        postedAt: refundDay,
        amountCents: 5000000,
        rawDescription: 'Incoming wire - earnest money',
        normalizedMerchant: 'EARNEST MONEY',
        pending: false,
        categoryId: 'cat_housing',
      ),
    ];

    const housing = SpendCategory(
      id: 'cat_housing',
      name: 'Housing',
      sortOrder: 0,
      archived: false,
    );
    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: const [housing],
      endDate: end,
    );
    final housingSeries = bundle.categorySpend.firstWhere(
      (series) => series.id == 'cat_housing',
    );
    final topContributors = TrendPointContributors.topForSeries(
      series: housingSeries,
      tapDate: refundDay,
      transactions: transactions,
      categories: const [housing],
      groups: const [],
    );

    expect(topContributors, isNotEmpty);
    expect(topContributors.first.transaction.id, 'earnest');
    expect(topContributors.first.rawAmountCents, 5000000);
    expect(topContributors.first.smoothedContributionCents, lessThan(0));
  });

  test('guide series returns no contributors', () {
    final start = DateTime(2024, 1, 1);
    final end = start.add(const Duration(days: 40));
    final transactions = [
      BankTransaction(
        id: 'income',
        accountId: 'a1',
        externalId: 'i1',
        postedAt: start,
        amountCents: 500000,
        rawDescription: 'Pay',
        normalizedMerchant: 'PAY',
        pending: false,
        categoryId: 'cat_income',
      ),
    ];
    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: const [
        SpendCategory(
          id: 'cat_income',
          name: 'Income',
          sortOrder: 0,
          archived: false,
        ),
      ],
      endDate: end,
    );
    final guide = bundle.cashFlows.firstWhere(
      (series) => series.id == TrendChartCatalog.fireSavingsGuideSeriesId,
    );
    expect(
      TrendPointContributors.topForSeries(
        series: guide,
        tapDate: end,
        transactions: transactions,
        categories: const [],
        groups: const [],
      ),
      isEmpty,
    );
  });
}
