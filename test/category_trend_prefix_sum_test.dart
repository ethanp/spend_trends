import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/annual_pace_smoother.dart';
import 'package:spend_trends/features/trends/build_trends_charts.dart';
import 'package:spend_trends/features/trends/hann_annual_pace_kernel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hann pace annualizes a constant daily spend', () {
    // Constant $1/day → annual pace is always $365 once annualized.
    final start = DateTime(2024, 1, 1);
    final transactions = List.generate(
      10,
      (dayOffset) => BankTransaction(
        id: 't$dayOffset',
        accountId: 'a1',
        externalId: 'e$dayOffset',
        postedAt: start.add(Duration(days: dayOffset)),
        amountCents: -100,
        rawDescription: 'Coffee',
        normalizedMerchant: 'COFFEE',
        pending: false,
        categoryId: 'cat_dining',
      ),
    );
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

    final dining = bundle.categorySpend.firstWhere(
      (series) => series.id == 'cat_dining',
    );
    expect(dining.points.length, 10);
    expect(dining.points.first.rollingCents, closeTo(36500, 0.01));
    expect(dining.points[4].rollingCents, closeTo(36500, 0.01));
    expect(dining.points.last.rollingCents, closeTo(36500, 0.01));
    expect(dining.points.first.smoothedCents, closeTo(36500, 0.01));
  });

  test('kernel support is ±halfWidth and fades toward the edge', () {
    const kernel = HannAnnualPaceKernel();
    const lastDayIndex = 2000;
    const centerIndex = 1000;

    final samples = kernel.normalizedSamples(
      centerIndex: centerIndex,
      historyStartIndex: 0,
      lastDayIndex: lastDayIndex,
    );
    expect(samples, isNotEmpty);
    // Exact ±halfWidth has Hann weight 0, so support is open at the edges.
    expect(samples.first.dayIndex, centerIndex - kernel.halfWidthDays + 1);
    expect(samples.last.dayIndex, centerIndex + kernel.halfWidthDays - 1);

    final centerWeight = samples
        .firstWhere((sample) => sample.dayIndex == centerIndex)
        .weight;
    final nearEdgeWeight = samples
        .firstWhere(
          (sample) => sample.dayIndex == centerIndex + kernel.halfWidthDays - 1,
        )
        .weight;
    expect(centerWeight, greaterThan(nearEdgeWeight));

    final weightSum = samples.fold<double>(
      0,
      (sum, sample) => sum + sample.weight,
    );
    expect(weightSum, closeTo(1.0, 1e-9));
  });

  test('long constant spend stays flat at year pace under Hann kernel', () {
    final start = DateTime(2024, 1, 1);
    final end = DateTime(2025, 12, 31);
    final transactions = <BankTransaction>[
      for (
        var day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))
      )
        BankTransaction(
          id: 'd${day.year}_${day.month}_${day.day}',
          accountId: 'a1',
          externalId: 'e${day.year}_${day.month}_${day.day}',
          postedAt: day,
          amountCents: -100,
          rawDescription: 'Coffee',
          normalizedMerchant: 'COFFEE',
          pending: false,
          categoryId: 'cat_dining',
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
        ),
      ],
      endDate: end,
    );
    final dining = bundle.categorySpend.firstWhere(
      (series) => series.id == 'cat_dining',
    );

    expect(dining.points.first.rollingCents, closeTo(36500, 0.01));
    expect(dining.points.last.rollingCents, closeTo(36500, 0.01));
    expect(dining.points.first.smoothedCents, closeTo(36500, 1));
    expect(dining.points.last.smoothedCents, closeTo(36500, 1));
  });

  test('same-day impulse contributes more than a far-edge impulse', () {
    const smoother = AnnualPaceSmoother.standard;
    const tapIndex = 1000;
    const lastDayIndex = 2000;
    const historyStartIndex = 0;
    const amountCents = 10000.0;

    final atCenter = smoother.impulseContributionCents(
      amountCents: amountCents,
      impulseIndex: tapIndex,
      tapIndex: tapIndex,
      historyStartIndex: historyStartIndex,
      lastDayIndex: lastDayIndex,
    );
    final nearEdge = smoother.impulseContributionCents(
      amountCents: amountCents,
      impulseIndex: tapIndex + smoother.halfWidthDays - 1,
      tapIndex: tapIndex,
      historyStartIndex: historyStartIndex,
      lastDayIndex: lastDayIndex,
    );
    expect(atCenter, greaterThan(nearEdge));
    expect(nearEdge, greaterThan(0));
  });
}
