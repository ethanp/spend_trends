import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/build_trends_charts.dart';
import 'package:spend_trends/features/trends/centered_moving_average.dart';
import 'package:spend_trends/features/trends/net_worth_component_history.dart';
import 'package:spend_trends/features/trends/net_worth_trend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';

void main() {
  test('daily net worth walks balances back through later transactions', () {
    final day0 = DateTime(2024, 1, 1);
    final day1 = DateTime(2024, 1, 2);
    final day2 = DateTime(2024, 1, 3);
    final accounts = [
      const Account(
        id: 'a1',
        externalId: 'ext1',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 10000,
        status: AccountStatus.ok,
      ),
      const Account(
        id: 'a2',
        externalId: 'ext2',
        name: 'Card',
        currency: 'USD',
        balanceCents: -3000,
        status: AccountStatus.ok,
      ),
    ];
    // Current NW = 7000. After day1 deposit +2000 and day2 spend -500
    // were applied to reach that balance:
    // NW(day2) = 7000
    // NW(day1) = 7000 - (-500) = 7500
    // NW(day0) = 7500 - 2000 = 5500
    final transactions = [
      BankTransaction(
        id: 'deposit',
        accountId: 'a1',
        externalId: 'd1',
        postedAt: day1,
        amountCents: 2000,
        rawDescription: 'Pay',
        normalizedMerchant: 'PAY',
        pending: false,
      ),
      BankTransaction(
        id: 'spend',
        accountId: 'a1',
        externalId: 's1',
        postedAt: day2,
        amountCents: -500,
        rawDescription: 'Shop',
        normalizedMerchant: 'SHOP',
        pending: false,
      ),
    ];

    final daily = NetWorthTrend.dailyCents(
      accounts: accounts,
      transactions: transactions,
      chartDates: [day0, day1, day2],
    );

    // Checking activity starts day1 → day0 contribution 0.
    // Card has no txns → only present on the last chart day.
    // day2: 10000 + (-3000) = 7000
    // day1: 10500 + 0 = 10500
    // day0: 0
    expect(daily, [0.0, 10500.0, 7000.0]);

    final checkingDaily = NetWorthTrend.accountDailyCents(
      account: accounts[0],
      transactions: transactions,
      chartDates: [day0, day1, day2],
    );
    // Checking ends at 10000; day2 spend -500, day1 deposit +2000.
    // Before first txn (day1) → 0.
    expect(checkingDaily, [0.0, 10500.0, 10000.0]);

    final cardDaily = NetWorthTrend.accountDailyCents(
      account: accounts[1],
      transactions: transactions,
      chartDates: [day0, day1, day2],
    );
    // No card transactions → known only from balanceAsOf (null) → last chart day.
    expect(cardDaily, [0.0, 0.0, -3000.0]);
  });

  test(
    'investment balance with no transactions stays at zero until balanceAsOf',
    () {
      final day0 = DateTime(2024, 1, 1);
      final day1 = DateTime(2024, 1, 2);
      final day2 = DateTime(2024, 1, 3);
      const m1 = Account(
        id: 'm1',
        externalId: 'ext-m1',
        name: 'Account',
        currency: 'USD',
        balanceCents: 114817902,
        balanceAsOf: null, // falls back to chart end
        status: AccountStatus.ok,
      );

      final daily = NetWorthTrend.accountDailyCents(
        account: m1,
        transactions: const [],
        chartDates: [day0, day1, day2],
      );
      expect(daily, [0.0, 0.0, 114817902.0]);

      final withAsOf = NetWorthTrend.accountDailyCents(
        account: Account(
          id: m1.id,
          externalId: m1.externalId,
          name: m1.name,
          currency: m1.currency,
          balanceCents: m1.balanceCents,
          balanceAsOf: day1,
          status: AccountStatus.ok,
        ),
        transactions: const [],
        chartDates: [day0, day1, day2],
      );
      expect(withAsOf, [0.0, 114817902.0, 114817902.0]);
    },
  );

  test('series includes total plus dashed liability account lines', () {
    final day0 = DateTime(2024, 1, 1);
    final chartDates = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++)
        day0.add(Duration(days: dayOffset)),
    ];
    final accounts = [
      const Account(
        id: 'checking',
        externalId: 'ext1',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 500000,
        status: AccountStatus.ok,
        kind: AccountKind.checking,
      ),
      const Account(
        id: 'mortgage',
        externalId: 'ext2',
        name: 'Mortgage',
        currency: 'USD',
        balanceCents: -200000,
        status: AccountStatus.ok,
        kind: AccountKind.loans,
      ),
    ];

    final series = NetWorthTrend.series(
      accounts: accounts,
      transactions: const [],
      chartDates: chartDates,
    );

    expect(series.map((entry) => entry.id).toList(), [
      TrendChartCatalog.netWorthSeriesId,
      TrendChartCatalog.accountSeriesId('checking'),
      TrendChartCatalog.accountSeriesId('mortgage'),
    ]);
    expect(series[1].dotted, isFalse);
    expect(series[2].dotted, isTrue);
    expect(series[2].name, 'Mortgage');
    expect(series[2].points.last.rollingCents, closeTo(200000, 0.01));
    expect(series[1].legendGroup, 'Checking');
    expect(series[2].legendGroup, 'Loans');
  });

  test('account series are ordered by kind then balance magnitude', () {
    final day0 = DateTime(2024, 1, 1);
    final chartDates = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++)
        day0.add(Duration(days: dayOffset)),
    ];
    final accounts = [
      const Account(
        id: 'm1',
        externalId: 'ext-m1',
        name: 'Account',
        currency: 'USD',
        balanceCents: 80000,
        connName: 'M1',
        status: AccountStatus.ok,
        kind: AccountKind.investment,
      ),
      const Account(
        id: 'ira',
        externalId: 'ext-ira',
        name: 'Roth IRA',
        currency: 'USD',
        balanceCents: 100000,
        status: AccountStatus.ok,
        kind: AccountKind.investment,
      ),
      const Account(
        id: 'schwab-b',
        externalId: 'ext-s2',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 20000,
        connName: 'Charles Schwab US',
        status: AccountStatus.ok,
        kind: AccountKind.checking,
      ),
      const Account(
        id: 'mortgage',
        externalId: 'ext-m',
        name: 'Mortgage',
        currency: 'USD',
        balanceCents: -500000,
        status: AccountStatus.ok,
        kind: AccountKind.loans,
      ),
      const Account(
        id: 'auto',
        externalId: 'ext-auto',
        name: 'Auto loan',
        currency: 'USD',
        balanceCents: -150000,
        status: AccountStatus.ok,
        kind: AccountKind.loans,
      ),
    ];

    final series = NetWorthTrend.series(
      accounts: accounts,
      transactions: const [],
      chartDates: chartDates,
    );
    final accountSeries = [
      for (final entry in series)
        if (entry.id != TrendChartCatalog.netWorthSeriesId) entry,
    ];

    expect(accountSeries.map((entry) => entry.legendGroup).toList(), [
      'Checking',
      'Investment',
      'Investment',
      'Loans',
      'Loans',
    ]);
    expect(accountSeries.map((entry) => entry.name).toList(), [
      'Charles Schwab US · Checking',
      'Roth IRA',
      'M1 · Account',
      'Mortgage',
      'Auto loan',
    ]);
  });

  test('account series colors share a kind hue with per-account shades', () {
    final day0 = DateTime(2024, 1, 1);
    final chartDates = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++)
        day0.add(Duration(days: dayOffset)),
    ];
    final accounts = [
      const Account(
        id: 'card-a',
        externalId: 'ext-ca',
        name: 'Card A',
        currency: 'USD',
        balanceCents: -10000,
        status: AccountStatus.ok,
        kind: AccountKind.creditCard,
      ),
      const Account(
        id: 'card-b',
        externalId: 'ext-cb',
        name: 'Card B',
        currency: 'USD',
        balanceCents: -20000,
        status: AccountStatus.ok,
        kind: AccountKind.creditCard,
      ),
      const Account(
        id: 'check',
        externalId: 'ext-ch',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 50000,
        status: AccountStatus.ok,
        kind: AccountKind.checking,
      ),
    ];

    final series = NetWorthTrend.series(
      accounts: accounts,
      transactions: const [],
      chartDates: chartDates,
    );
    final cardA = series.firstWhere((entry) => entry.name == 'Card A');
    final cardB = series.firstWhere((entry) => entry.name == 'Card B');
    final checking = series.firstWhere((entry) => entry.name == 'Checking');

    expect(cardA.lineColor, isNot(cardB.lineColor));
    expect(cardA.lineColor, isNot(checking.lineColor));
    expect(
      HSLColor.fromColor(cardA.lineColor).hue,
      closeTo(HSLColor.fromColor(cardB.lineColor).hue, 1.0),
    );
    expect(
      HSLColor.fromColor(cardA.lineColor).hue,
      isNot(closeTo(HSLColor.fromColor(checking.lineColor).hue, 20.0)),
    );
  });

  test('factory includes a net worth series when accounts exist', () {
    final start = DateTime(2024, 1, 1);
    final end = start.add(const Duration(days: 9));
    final accounts = [
      const Account(
        id: 'a1',
        externalId: 'ext1',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 500000,
        status: AccountStatus.ok,
      ),
    ];
    final transactions = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++)
        BankTransaction(
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
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: transactions,
      categories: const [],
      accounts: accounts,
      endDate: end,
    );

    expect(bundle.netWorth, isNotEmpty);
    expect(bundle.netWorth.first.id, TrendChartCatalog.netWorthSeriesId);
    expect(
      bundle.netWorth.first.points.last.rollingCents,
      closeTo(500000, 0.01),
    );
  });

  test('Copilot child history folds into SimpleFIN parent net worth', () {
    final day0 = DateTime(2024, 1, 1);
    final day1 = DateTime(2024, 1, 2);
    final day2 = DateTime(2024, 1, 3);
    final chartDates = [day0, day1, day2];
    final accounts = [
      const Account(
        id: 'simplefin',
        externalId: 'ACT-card',
        name: 'Venture X (1298)',
        currency: 'USD',
        balanceCents: 10000,
        status: AccountStatus.ok,
        kind: AccountKind.creditCard,
      ),
      const Account(
        id: 'copilot',
        externalId: 'copilot:Venture X:1298',
        name: 'Venture X ·1298',
        currency: 'USD',
        balanceCents: 0,
        status: AccountStatus.ok,
        kind: AccountKind.creditCard,
        belongsToAccountId: 'simplefin',
      ),
    ];
    // Parent ends at 10000. Day2 SimpleFIN spend -500, day1 Copilot spend -2000.
    // Activity starts day1 → day0 contribution is 0 (knownFrom cutoff).
    // day2: 10000
    // day1: 10000 - (-500) = 10500
    // day0: 0
    final transactions = [
      BankTransaction(
        id: 'copilot-spend',
        accountId: 'copilot',
        externalId: 'c1',
        postedAt: day1,
        amountCents: -2000,
        rawDescription: 'Shop',
        normalizedMerchant: 'SHOP',
        pending: false,
      ),
      BankTransaction(
        id: 'simplefin-spend',
        accountId: 'simplefin',
        externalId: 's1',
        postedAt: day2,
        amountCents: -500,
        rawDescription: 'Cafe',
        normalizedMerchant: 'CAFE',
        pending: false,
      ),
    ];

    final daily = NetWorthTrend.dailyCents(
      accounts: accounts,
      transactions: transactions,
      chartDates: chartDates,
    );
    expect(daily, [0.0, 10500.0, 10000.0]);

    // Without folding, parent alone would only see day2 → day1 would be 0.
    final parentOnly = NetWorthTrend.accountDailyCents(
      account: accounts[0],
      transactions: transactions,
      chartDates: chartDates,
    );
    expect(parentOnly, [0.0, 0.0, 10000.0]);

    final series = NetWorthTrend.series(
      accounts: accounts,
      transactions: transactions,
      chartDates: [
        for (var dayOffset = 0; dayOffset < 10; dayOffset++)
          day0.add(Duration(days: dayOffset)),
      ],
    );
    expect(series.map((entry) => entry.id).toList(), [
      TrendChartCatalog.netWorthSeriesId,
      TrendChartCatalog.accountSeriesId('simplefin'),
    ]);
    expect(
      series.any(
        (entry) => entry.id == TrendChartCatalog.accountSeriesId('copilot'),
      ),
      isFalse,
    );
  });

  test('SimpleFIN prior loan drops out of current net worth', () {
    final day0 = DateTime(2024, 1, 1);
    final day1 = DateTime(2024, 1, 2);
    final day2 = DateTime(2024, 1, 3);
    final chartDates = [day0, day1, day2];
    const currentServicer = Account(
      id: 'carrington',
      externalId: 'ACT-carrington',
      name: 'Account (2056)',
      currency: 'USD',
      balanceCents: -52768012,
      status: AccountStatus.ok,
      kind: AccountKind.loans,
    );
    const priorServicer = Account(
      id: 'valon',
      externalId: 'ACT-valon',
      name: 'Mortgage 4561',
      currency: 'USD',
      balanceCents: -52820000,
      status: AccountStatus.ok,
      kind: AccountKind.loans,
      belongsToAccountId: 'carrington',
    );
    expect(
      NetWorthTrend.currentCents(
        accounts: [currentServicer, priorServicer],
        ownedAssets: const [],
      ),
      currentServicer.balanceCents,
    );

    final transactions = [
      BankTransaction(
        id: 'valon-payment',
        accountId: 'valon',
        externalId: 'v1',
        postedAt: day1,
        amountCents: 50000,
        rawDescription: 'Mortgage',
        normalizedMerchant: 'VALON',
        pending: false,
      ),
    ];
    expect(
      NetWorthTrend.dailyCents(
        accounts: [currentServicer, priorServicer],
        transactions: transactions,
        chartDates: chartDates,
      ),
      [
        0.0,
        currentServicer.balanceCents.toDouble(),
        currentServicer.balanceCents.toDouble(),
      ],
    );
    expect(
      NetWorthTrend.accountDailyCents(
        account: currentServicer,
        transactions: transactions,
        chartDates: chartDates,
      ),
      [0.0, 0.0, currentServicer.balanceCents.toDouble()],
    );

    final series = NetWorthTrend.series(
      accounts: [currentServicer, priorServicer],
      transactions: transactions,
      chartDates: [
        for (var dayOffset = 0; dayOffset < 10; dayOffset++)
          day0.add(Duration(days: dayOffset)),
      ],
    );
    expect(
      series.any(
        (entry) => entry.id == TrendChartCatalog.accountSeriesId('valon'),
      ),
      isFalse,
    );
    expect(
      series.any(
        (entry) => entry.id == TrendChartCatalog.accountSeriesId('carrington'),
      ),
      isTrue,
    );
  });

  test('owned assets add to daily net worth and step on re-valuation', () {
    final day0 = DateTime(2024, 1, 1);
    final chartDates = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++)
        day0.add(Duration(days: dayOffset)),
    ];
    const accounts = [
      Account(
        id: 'checking',
        externalId: 'ext-checking',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 10000,
        status: AccountStatus.ok,
        kind: AccountKind.checking,
      ),
    ];
    final ownedAssets = [
      OwnedAssetWithValuations(
        asset: const OwnedAsset(
          id: 'home',
          name: 'Home',
          kind: OwnedAssetKind.home,
        ),
        valuations: [
          OwnedAssetValuation(
            id: 'v1',
            ownedAssetId: 'home',
            valueCents: 20000000,
            valuedOn: DateTime(2024, 1, 1),
          ),
          OwnedAssetValuation(
            id: 'v2',
            ownedAssetId: 'home',
            valueCents: 25000000,
            valuedOn: DateTime(2024, 1, 5),
          ),
        ],
      ),
    ];

    final daily = NetWorthTrend.dailyCents(
      accounts: accounts,
      transactions: const [],
      chartDates: chartDates,
      ownedAssets: ownedAssets,
    );

    // Checking has no txns → only the last chart day.
    expect(daily[0], 20000000.0);
    expect(daily[3], 20000000.0);
    expect(daily[4], 25000000.0);
    expect(daily[8], 25000000.0);
    expect(daily[9], 25010000.0);

    final series = NetWorthTrend.series(
      accounts: accounts,
      transactions: const [],
      chartDates: chartDates,
      ownedAssets: ownedAssets,
    );
    expect(
      series.map((entry) => entry.id).toList(),
      containsAll([
        TrendChartCatalog.netWorthSeriesId,
        TrendChartCatalog.accountSeriesId('checking'),
        TrendChartCatalog.ownedAssetSeriesId('home'),
      ]),
    );
    final homeSeries = series.firstWhere(
      (entry) => entry.id == TrendChartCatalog.ownedAssetSeriesId('home'),
    );
    expect(homeSeries.legendGroup, AccountKind.nonFinancialAssets.legendLabel);
    expect(homeSeries.points[0].rollingCents, 20000000.0);
    expect(homeSeries.points[4].rollingCents, 25000000.0);
  });

  test('manual account steps between recorded balances, ignoring txns', () {
    final day0 = DateTime(2024, 1, 1);
    final chartDates = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++)
        day0.add(Duration(days: dayOffset)),
    ];
    final accounts = [
      Account(
        id: 'hsa',
        externalId: 'manual:hsa',
        name: 'HSA',
        currency: 'USD',
        balanceCents: 150000,
        balanceAsOf: DateTime(2024, 1, 6),
        status: AccountStatus.ok,
        kind: AccountKind.investment,
      ),
    ];
    final transactions = [
      BankTransaction(
        id: 'contribution',
        accountId: 'hsa',
        externalId: 'c1',
        postedAt: DateTime(2024, 1, 4),
        amountCents: 99999,
        rawDescription: 'Contribution',
        normalizedMerchant: 'CONTRIBUTION',
        pending: false,
      ),
    ];
    final balanceSnapshots = [
      AccountBalanceSnapshot(
        id: 'later',
        accountId: 'hsa',
        balanceCents: 150000,
        recordedOn: DateTime(2024, 1, 6),
      ),
      AccountBalanceSnapshot(
        id: 'earlier',
        accountId: 'hsa',
        balanceCents: 100000,
        recordedOn: DateTime(2024, 1, 3),
      ),
    ];

    final daily = NetWorthTrend.dailyCents(
      accounts: accounts,
      transactions: transactions,
      chartDates: chartDates,
      balanceSnapshots: balanceSnapshots,
    );

    expect(daily[1], 0.0);
    expect(daily[2], 100000.0);
    expect(daily[4], 100000.0);
    expect(daily[5], 150000.0);
    expect(daily[9], 150000.0);
  });

  test('factory includes owned assets in the net worth series', () {
    final start = DateTime(2024, 1, 1);
    final end = start.add(const Duration(days: 9));
    final ownedAssets = [
      OwnedAssetWithValuations(
        asset: const OwnedAsset(
          id: 'car',
          name: 'Car',
          kind: OwnedAssetKind.vehicle,
        ),
        valuations: [
          OwnedAssetValuation(
            id: 'v1',
            ownedAssetId: 'car',
            valueCents: 1800000,
            valuedOn: start,
          ),
        ],
      ),
    ];

    final bundle = const BuildTrendsCharts().build(
      transactions: const [],
      categories: const [],
      ownedAssets: ownedAssets,
      endDate: end,
    );

    expect(bundle.netWorth, isNotEmpty);
    expect(
      bundle.netWorth.any(
        (entry) => entry.id == TrendChartCatalog.ownedAssetSeriesId('car'),
      ),
      isTrue,
    );
    expect(
      bundle.netWorth.first.points.last.rollingCents,
      closeTo(1800000, 0.01),
    );
  });

  test('afternoon balanceAsOf on the last chart day still lists a 529', () {
    final lastDay = DateTime(2024, 3, 1);
    final chartDates = [
      for (var dayOffset = 0; dayOffset < 10; dayOffset++)
        lastDay.subtract(Duration(days: 9 - dayOffset)),
    ];
    final plan529 = Account(
      id: '529',
      externalId: 'ext-529',
      name: 'Schwab 529 Plan ...-01 (01)',
      currency: 'USD',
      balanceCents: 6173889,
      balanceAsOf: DateTime(2024, 3, 1, 9, 16, 43),
      status: AccountStatus.ok,
      kind: AccountKind.investment,
    );
    const pie = Account(
      id: 'pie',
      externalId: 'ext-pie',
      name: 'Pie',
      currency: 'USD',
      balanceCents: 121670815,
      status: AccountStatus.ok,
      kind: AccountKind.investment,
    );

    final series = NetWorthTrend.series(
      accounts: [pie, plan529],
      transactions: const [],
      chartDates: chartDates,
    );
    final planSeries = series.firstWhere(
      (entry) => entry.id == TrendChartCatalog.accountSeriesId('529'),
    );
    expect(planSeries.name, contains('529'));
    expect(planSeries.legendGroup, 'Investment');
    expect(planSeries.points.last.rollingCents, closeTo(6173889, 0.01));
    expect(planSeries.points.last.smoothedCents, closeTo(6173889, 0.01));
  });

  test(
    'a loan first known on the last day keeps its full raw and smoothed tip',
    () {
      final lastDay = DateTime(2024, 3, 1);
      final chartDates = [
        for (var dayOffset = 0; dayOffset < 60; dayOffset++)
          lastDay.subtract(Duration(days: 59 - dayOffset)),
      ];
      final mortgage = Account(
        id: 'mortgage',
        externalId: 'ext-mortgage',
        name: 'Lancefield',
        currency: 'USD',
        balanceCents: -36015288,
        balanceAsOf: lastDay,
        status: AccountStatus.ok,
        kind: AccountKind.loans,
      );
      final plan529 = Account(
        id: '529',
        externalId: 'ext-529',
        name: '529 Plan',
        currency: 'USD',
        balanceCents: 6173889,
        balanceAsOf: lastDay,
        status: AccountStatus.ok,
        kind: AccountKind.investment,
      );

      final series = NetWorthTrend.series(
        accounts: [mortgage, plan529],
        transactions: const [],
        chartDates: chartDates,
      );
      final mortgageSeries = series.firstWhere(
        (entry) => entry.id == TrendChartCatalog.accountSeriesId('mortgage'),
      );
      final planSeries = series.firstWhere(
        (entry) => entry.id == TrendChartCatalog.accountSeriesId('529'),
      );
      final total = series.firstWhere(
        (entry) => entry.id == TrendChartCatalog.netWorthSeriesId,
      );

      expect(mortgageSeries.points[58].rollingCents, 0);
      expect(mortgageSeries.points[58].smoothedCents, 0);
      expect(mortgageSeries.points.last.rollingCents, closeTo(36015288, 0.01));
      expect(mortgageSeries.points.last.smoothedCents, closeTo(36015288, 0.01));
      expect(planSeries.points.last.rollingCents, closeTo(6173889, 0.01));
      expect(planSeries.points.last.smoothedCents, closeTo(6173889, 0.01));
      expect(
        total.points.last.rollingCents,
        closeTo(-36015288 + 6173889, 0.01),
      );
      expect(
        total.points.last.smoothedCents,
        closeTo(-36015288 + 6173889, 0.01),
      );
    },
  );

  test(
    'established account history still uses the three-pass 43-day smoother',
    () {
      final start = DateTime(2024, 1, 1);
      final chartDates = [
        for (var dayOffset = 0; dayOffset < 60; dayOffset++)
          start.add(Duration(days: dayOffset)),
      ];
      const checking = Account(
        id: 'checking',
        externalId: 'ext-checking',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 60000,
        status: AccountStatus.ok,
        kind: AccountKind.checking,
      );
      final transactions = [
        for (var dayOffset = 0; dayOffset < 60; dayOffset++)
          BankTransaction(
            id: 't$dayOffset',
            accountId: 'checking',
            externalId: 'e$dayOffset',
            postedAt: start.add(Duration(days: dayOffset)),
            amountCents: 1000,
            rawDescription: 'Pay',
            normalizedMerchant: 'PAY',
            pending: false,
          ),
      ];
      final rawDaily = NetWorthTrend.accountDailyCents(
        account: checking,
        transactions: transactions,
        chartDates: chartDates,
      );
      final expectedSmoothed = CenteredMovingAverage.standard.smoothValues(
        rawDaily,
      );

      final series = NetWorthTrend.series(
        accounts: [checking],
        transactions: transactions,
        chartDates: chartDates,
      );
      final checkingSeries = series.firstWhere(
        (entry) => entry.id == TrendChartCatalog.accountSeriesId('checking'),
      );
      expect(checkingSeries.points.last.rollingCents, closeTo(60000, 0.01));
      for (var dayIndex = 0; dayIndex < chartDates.length; dayIndex++) {
        expect(
          checkingSeries.points[dayIndex].smoothedCents,
          closeTo(expectedSmoothed[dayIndex], 0.01),
        );
      }
    },
  );

  test(
    'total smoothed cents are the signed sum of component-smoothed cents',
    () {
      final lastDay = DateTime(2024, 3, 1);
      final chartDates = [
        for (var dayOffset = 0; dayOffset < 60; dayOffset++)
          lastDay.subtract(Duration(days: 59 - dayOffset)),
      ];
      final checking = Account(
        id: 'checking',
        externalId: 'ext-checking',
        name: 'Checking',
        currency: 'USD',
        balanceCents: 10000000,
        balanceAsOf: DateTime(2024, 1, 2),
        status: AccountStatus.ok,
        kind: AccountKind.checking,
      );
      final mortgage = Account(
        id: 'mortgage',
        externalId: 'ext-mortgage',
        name: 'Mortgage',
        currency: 'USD',
        balanceCents: -4000000,
        balanceAsOf: lastDay,
        status: AccountStatus.ok,
        kind: AccountKind.loans,
      );
      final ownedAssets = [
        OwnedAssetWithValuations(
          asset: const OwnedAsset(
            id: 'home',
            name: 'Home',
            kind: OwnedAssetKind.home,
          ),
          valuations: [
            OwnedAssetValuation(
              id: 'v1',
              ownedAssetId: 'home',
              valueCents: 20000000,
              valuedOn: DateTime(2024, 1, 15),
            ),
          ],
        ),
      ];

      final series = NetWorthTrend.series(
        accounts: [checking, mortgage],
        transactions: const [],
        chartDates: chartDates,
        ownedAssets: ownedAssets,
      );
      final total = series.firstWhere(
        (entry) => entry.id == TrendChartCatalog.netWorthSeriesId,
      );
      expect(
        total.latestRollingCents,
        NetWorthTrend.currentCents(
          accounts: [checking, mortgage],
          ownedAssets: ownedAssets,
        ),
      );

      final checkingSeries = series.firstWhere(
        (entry) => entry.id == TrendChartCatalog.accountSeriesId('checking'),
      );
      final mortgageSeries = series.firstWhere(
        (entry) => entry.id == TrendChartCatalog.accountSeriesId('mortgage'),
      );
      final homeSeries = series.firstWhere(
        (entry) => entry.id == TrendChartCatalog.ownedAssetSeriesId('home'),
      );
      for (var dayIndex = 0; dayIndex < chartDates.length; dayIndex++) {
        expect(
          total.points[dayIndex].smoothedCents,
          closeTo(
            checkingSeries.points[dayIndex].smoothedCents -
                mortgageSeries.points[dayIndex].smoothedCents +
                homeSeries.points[dayIndex].smoothedCents,
            0.01,
          ),
        );
      }
    },
  );

  test('component history smooths only the known suffix', () {
    final history = NetWorthComponentHistory(
      rawDailyCents: [0, 0, 0, 100000, 100000],
      firstKnownDayIndex: 3,
    );
    expect(history.smoothedDailyCents.sublist(0, 3), [0, 0, 0]);
    expect(history.smoothedDailyCents[3], 100000);
    expect(history.smoothedDailyCents[4], 100000);
  });

  test(
    'balance history series is omitted when only a same-day snapshot exists',
    () {
      const retirement = Account(
        id: '401k',
        externalId: 'ext-401k',
        name: 'Sunrun 401k',
        currency: 'USD',
        balanceCents: 3831619,
        status: AccountStatus.ok,
        kind: AccountKind.investment,
      );
      expect(
        NetWorthTrend.balanceHistorySeries(
          account: retirement,
          accounts: [retirement],
          transactions: const [],
          endDate: DateTime(2026, 9, 6),
        ),
        isNull,
      );
    },
  );

  test('balance history series starts on the first known day', () {
    const checking = Account(
      id: 'checking',
      externalId: 'ext-checking',
      name: 'Checking',
      currency: 'USD',
      balanceCents: 125000,
      status: AccountStatus.ok,
      kind: AccountKind.checking,
    );
    final firstPostedOn = DateTime(2026, 8, 1);
    final series = NetWorthTrend.balanceHistorySeries(
      account: checking,
      accounts: [checking],
      transactions: [
        BankTransaction(
          id: 't1',
          accountId: checking.id,
          externalId: 'e1',
          postedAt: firstPostedOn,
          amountCents: 5000,
          rawDescription: 'Pay',
          normalizedMerchant: 'PAY',
          pending: false,
        ),
      ],
      endDate: DateTime(2026, 9, 6),
    );

    expect(series, isNotNull);
    expect(series!.points.first.date, firstPostedOn);
    expect(series.points.last.rollingCents, 125000);
    for (final point in series.points) {
      expect(point.rollingCents, greaterThan(0));
    }
  });

  test(
    'balance history series holds a multi-day snapshot at the live balance',
    () {
      final knownFrom = DateTime(2026, 8, 1);
      final retirement = Account(
        id: '401k',
        externalId: 'ext-401k',
        name: 'Sunrun 401k',
        currency: 'USD',
        balanceCents: 3831619,
        balanceAsOf: knownFrom,
        status: AccountStatus.ok,
        kind: AccountKind.investment,
      );
      final series = NetWorthTrend.balanceHistorySeries(
        account: retirement,
        accounts: [retirement],
        transactions: const [],
        endDate: DateTime(2026, 9, 6),
      );

      expect(series, isNotNull);
      expect(series!.points.first.date, knownFrom);
      expect(series.points.first.rollingCents, 3831619);
      expect(series.points.last.rollingCents, 3831619);
    },
  );
}
