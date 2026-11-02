import 'dart:math' as math;

import 'package:spend_trends/ui/theme/owned_asset_kind_color.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/accounts/account_balance_snapshot.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart'
    show AccountKind;
import 'package:spend_trends/domain/accounts/imported_net_worth_day.dart';
import 'package:spend_trends/domain/accounts/owned_asset.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/domain/trends/category_trend_point.dart';
import 'package:spend_trends/ui/trends/category_trend_series.dart';
import 'package:spend_trends/domain/trends/centered_moving_average.dart';
import 'package:spend_trends/domain/trends/net_worth_component_history.dart';
import 'package:spend_trends/ui/trends/trend_chart_catalog.dart';
import 'package:spend_trends/ui/theme/account_kind_color.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

/// Reconstructs daily net worth from current balances + later transactions.
class NetWorthTrend._() {
  static int currentCents({
    required Iterable<Account> accounts,
    required Iterable<OwnedAssetWithValuations> ownedAssets,
  }) {
    var currentCents = 0;
    for (final account in accounts) {
      if (!account.countsTowardNetWorth) continue;
      currentCents += account.balanceCents;
    }
    for (final ownedAsset in ownedAssets) {
      currentCents += ownedAsset.currentValueCents;
    }
    return currentCents;
  }

  /// Sum of per-account [accountDailyCents] (keeps total NW consistent with
  /// breakdown lines, including investment accounts with no transaction history).
  ///
  /// Child accounts ([Account.belongsToAccountId]) are skipped; their
  /// transactions fold into the parent walk-back.
  static List<double> dailyCents({
    required List<Account> accounts,
    required List<BankTransaction> transactions,
    required List<DateTime> chartDates,
    List<OwnedAssetWithValuations> ownedAssets = const [],
    List<AccountBalanceSnapshot> balanceSnapshots = const [],
  }) {
    if (chartDates.isEmpty) return const [];
    final totals = List<double>.filled(chartDates.length, 0);
    for (final component in _signedComponents(
      accounts: accounts,
      accountRows: _AccountRows(
        transactions: transactions,
        balanceSnapshots: balanceSnapshots,
      ),
      chart: _ChartDays(chartDates),
      ownedAssets: ownedAssets,
    )) {
      for (var dayIndex = 0; dayIndex < chartDates.length; dayIndex++) {
        totals[dayIndex] += component.history.rawDailyCents[dayIndex];
      }
    }
    return totals;
  }

  /// Walks [account.balanceCents] back through that account's transactions.
  ///
  /// Before the account's first known activity (earliest transaction, else
  /// [Account.balanceAsOf], else the chart end), contribution is 0. That stops
  /// investment balances with no SimpleFIN history (e.g. M1) from painting
  /// today's market value across the entire chart.
  ///
  /// When [includeAccountIds] is set (parent + Copilot children), those
  /// accounts' transactions all feed the walk-back from this balance.
  static List<double> accountDailyCents({
    required Account account,
    required List<BankTransaction> transactions,
    required List<DateTime> chartDates,
    Set<String>? includeAccountIds,
  }) {
    return _accountHistory(
      account: account,
      accountRows: _AccountRows(transactions: transactions),
      chart: _ChartDays(chartDates),
      includeAccountIds: includeAccountIds ?? {account.id},
    ).rawDailyCents;
  }

  /// Total net worth plus per-account contribution lines.
  ///
  /// [chartDates] are consecutive local-midnight days, ascending. Day math
  /// runs on their [CalendarDay]s; the dates only label the points.
  ///
  /// Account breakdowns plot [abs] magnitude so liabilities sit above zero;
  /// a dashed stroke marks that the signed balance is negative.
  /// Child accounts are omitted; their history folds into the parent line.
  static List<CategoryTrendSeries> series({
    required List<Account> accounts,
    required List<BankTransaction> transactions,
    required List<DateTime> chartDates,
    List<OwnedAssetWithValuations> ownedAssets = const [],
    List<AccountBalanceSnapshot> balanceSnapshots = const [],
    List<ImportedNetWorthDay> importedNetWorthDays = const [],
  }) {
    if ((accounts.isEmpty && ownedAssets.isEmpty) || chartDates.length < 2) {
      return const [];
    }

    final chart = _ChartDays(chartDates);
    final components = _signedComponents(
      accounts: accounts,
      accountRows: _AccountRows(
        transactions: transactions,
        balanceSnapshots: balanceSnapshots,
      ),
      chart: chart,
      ownedAssets: ownedAssets,
    );
    final netWorthSeries = _totalSeries(
      components: components,
      chart: chart,
      importedNetWorthDays: importedNetWorthDays,
    );
    if (netWorthSeries == null) return const [];

    final assetSales = _cumulativeAssetSalesSeries(
      transactions: transactions,
      chart: chart,
    );
    final breakdown = _breakdownSeries(components, chartDates);
    return [netWorthSeries, ?assetSales, ...breakdown];
  }

  /// Running total of Asset sale proceeds as unsmoothed steps, so each sale
  /// reads as a lump sum beside net worth instead of a savings ramp.
  static CategoryTrendSeries? _cumulativeAssetSalesSeries({
    required List<BankTransaction> transactions,
    required _ChartDays chart,
  }) {
    final proceedsByDay = <CalendarDay, int>{};
    for (final transaction in transactions) {
      if (!SpecialCategory.isAssetSaleId(transaction.categoryId)) {
        continue;
      }
      proceedsByDay.update(
        transaction.postedDay,
        (priorCents) => priorCents + transaction.amountCents,
        ifAbsent: () => transaction.amountCents,
      );
    }
    if (proceedsByDay.isEmpty) return null;

    var runningCents = 0.0;
    final points = <CategoryTrendPoint>[];
    for (var dayIndex = 0; dayIndex < chart.length; dayIndex++) {
      runningCents += proceedsByDay[chart.days[dayIndex]] ?? 0;
      points.add(
        CategoryTrendPoint(
          date: chart.dates[dayIndex],
          rollingCents: runningCents,
          smoothedCents: runningCents,
        ),
      );
    }
    return _seriesFromPoints(
      id: TrendChartCatalog.assetSalesSeriesId,
      name: 'Asset sales',
      lineColor: TrendChartCatalog.assetSalesLineColor,
      legendCaption: 'Lump sums',
      points: points,
    );
  }

  /// One account's reconstructed balance, starting on the first known day.
  ///
  /// Leading unknown days are omitted so a current snapshot does not paint a
  /// flat-zero line across the full Trends range. Returns null when fewer than
  /// two known days exist (live balance only, no posted history).
  static CategoryTrendSeries? balanceHistorySeries({
    required Account account,
    required List<Account> accounts,
    required List<BankTransaction> transactions,
    List<AccountBalanceSnapshot> balanceSnapshots = const [],
    DateTime? endDate,
  }) {
    final CalendarDay chartEnd = (endDate ?? DateTime.now()).calendarDay;
    final CalendarDay historyFloor =
        BankTransaction.completeHistoryStart.calendarDay;
    final includeAccountIds = _historyAccountIds(account, accounts);
    final accountRows = _AccountRows(
      transactions: transactions,
      balanceSnapshots: balanceSnapshots,
    );
    final postedAmounts = _postedDayAmounts(
      accountRows.transactionsFor(includeAccountIds),
    );
    final CalendarDay? firstSnapshotDay = accountRows
        .snapshotsFor(account.id)
        .firstOrNull
        ?.recordedDay;
    final CalendarDay? balanceAsOfDay = account.balanceAsOf?.calendarDay;
    final CalendarDay knownFrom = account.isValuedBySnapshots
        ? firstSnapshotDay ??
              postedAmounts.earliestDay ??
              balanceAsOfDay ??
              chartEnd
        : [
            ?firstSnapshotDay,
            ?postedAmounts.earliestDay,
            balanceAsOfDay ?? chartEnd,
          ].reduce((earliest, day) => day.isBefore(earliest) ? day : earliest);
    final CalendarDay chartStart = knownFrom.isBefore(historyFloor)
        ? historyFloor
        : knownFrom;
    if (chartEnd.daysSince(chartStart) < 1) return null;

    final chart = _ChartDays(_calendarDates(chartStart, chartEnd));
    if (chart.length < 2) return null;

    return _seriesFromHistory(
      component: _accountComponent(
        account: account,
        kind: account.kind,
        accountRows: accountRows,
        chart: chart,
        includeAccountIds: includeAccountIds,
      ),
      chartDates: chart.dates,
    );
  }

  static List<_SignedNetWorthComponent> _signedComponents({
    required List<Account> accounts,
    required _AccountRows accountRows,
    required _ChartDays chart,
    required List<OwnedAssetWithValuations> ownedAssets,
  }) {
    final roots = _rootAccounts(accounts);
    final childIdsByParent = _childIdsByParent(accounts);
    final components = <_SignedNetWorthComponent>[];
    var emittedOwnedAssets = false;
    for (final group in _accountsByKind(roots)) {
      for (final account in group.accounts) {
        components.add(
          _accountComponent(
            account: account,
            kind: group.kind,
            accountRows: accountRows,
            chart: chart,
            includeAccountIds: {account.id, ...?childIdsByParent[account.id]},
          ),
        );
      }
      if (group.kind == AccountKind.nonFinancialAssets) {
        components.addAll(
          _ownedAssetComponents(ownedAssets: ownedAssets, chart: chart),
        );
        emittedOwnedAssets = true;
      }
    }
    if (!emittedOwnedAssets) {
      components.addAll(
        _ownedAssetComponents(ownedAssets: ownedAssets, chart: chart),
      );
    }
    return components;
  }

  static _SignedNetWorthComponent _accountComponent({
    required Account account,
    required AccountKind kind,
    required _AccountRows accountRows,
    required _ChartDays chart,
    required Set<String> includeAccountIds,
  }) {
    return _SignedNetWorthComponent(
      id: TrendChartCatalog.accountSeriesId(account.id),
      name: account.displayNameWithInstitution,
      lineColor: AccountKindColor.forAccount(kind: kind, accountId: account.id),
      dotted: account.balanceCents < 0,
      legendGroup: kind.legendLabel,
      plotAbsoluteMagnitude: true,
      history: _balanceHistory(
        account: account,
        accountRows: accountRows,
        chart: chart,
        includeAccountIds: includeAccountIds,
      ),
    );
  }

  /// Each net-worth account's balance on each of [chartDates] (consecutive
  /// days), smoothed the way the net worth line sums it: 0 before the
  /// account is known. Linked prior accounts fold into their parent.
  static Map<Account, List<double>> smoothedBalanceCentsByAccount({
    required List<Account> accounts,
    required List<BankTransaction> transactions,
    required List<AccountBalanceSnapshot> balanceSnapshots,
    required List<DateTime> chartDates,
  }) {
    final childIdsByParent = _childIdsByParent(accounts);
    final accountRows = _AccountRows(
      transactions: transactions,
      balanceSnapshots: balanceSnapshots,
    );
    final chart = _ChartDays(chartDates);
    return {
      for (final account in _rootAccounts(accounts))
        account: _balanceHistory(
          account: account,
          accountRows: accountRows,
          chart: chart,
          includeAccountIds: {account.id, ...?childIdsByParent[account.id]},
        ).smoothedDailyCents,
    };
  }

  /// [ownedAsset]'s value on each of [chartDates], smoothed the way the net
  /// worth line sums it.
  static List<double> smoothedValueCents({
    required OwnedAssetWithValuations ownedAsset,
    required List<DateTime> chartDates,
  }) => _ownedAssetHistory(
    ownedAsset: ownedAsset,
    chart: _ChartDays(chartDates),
  ).smoothedDailyCents;

  static NetWorthComponentHistory _balanceHistory({
    required Account account,
    required _AccountRows accountRows,
    required _ChartDays chart,
    required Set<String> includeAccountIds,
  }) => account.isValuedBySnapshots
      ? _recordedBalanceHistory(
          account: account,
          snapshots: accountRows.snapshotsFor(account.id),
          chart: chart,
        )
      : _accountHistory(
          account: account,
          accountRows: accountRows,
          chart: chart,
          includeAccountIds: includeAccountIds,
        );

  /// A manual or history-import account steps between its recorded balances;
  /// before the first it is unknown. With none recorded, only today shows the
  /// balance.
  static NetWorthComponentHistory _recordedBalanceHistory({
    required Account account,
    required List<AccountBalanceSnapshot> snapshots,
    required _ChartDays chart,
  }) {
    if (chart.isEmpty) {
      return NetWorthComponentHistory(
        rawDailyCents: const [],
        firstKnownDayIndex: 0,
      );
    }
    if (snapshots.isEmpty) {
      return NetWorthComponentHistory(
        rawDailyCents: [
          ...List<double>.filled(chart.length - 1, 0),
          account.balanceCents.toDouble(),
        ],
        firstKnownDayIndex: chart.length - 1,
      );
    }
    final values = List<double>.filled(chart.length, 0);
    var nextSnapshotIndex = 0;
    double? recordedCents;
    for (var dayIndex = 0; dayIndex < chart.length; dayIndex++) {
      final CalendarDay day = chart.days[dayIndex];
      while (nextSnapshotIndex < snapshots.length &&
          !snapshots[nextSnapshotIndex].recordedDay.isAfter(day)) {
        recordedCents = snapshots[nextSnapshotIndex].balanceCents.toDouble();
        nextSnapshotIndex++;
      }
      values[dayIndex] = recordedCents ?? 0;
    }
    return NetWorthComponentHistory(
      rawDailyCents: values,
      firstKnownDayIndex: math.min(
        _firstIndexOnOrAfter(chart.days, snapshots.first.recordedDay),
        chart.length - 1,
      ),
    );
  }

  static List<_SignedNetWorthComponent> _ownedAssetComponents({
    required List<OwnedAssetWithValuations> ownedAssets,
    required _ChartDays chart,
  }) {
    final components = <_SignedNetWorthComponent>[];
    final sorted = [...ownedAssets]
      ..sort(
        (left, right) => right.currentValueCents.abs().compareTo(
          left.currentValueCents.abs(),
        ),
      );
    for (final ownedAsset in sorted) {
      components.add(
        _SignedNetWorthComponent(
          id: TrendChartCatalog.ownedAssetSeriesId(ownedAsset.asset.id),
          name: ownedAsset.asset.name,
          lineColor: ownedAsset.asset.kind.lineColor.shadeKeyedBy(
            ownedAsset.asset.id,
          ),
          legendGroup: AccountKind.nonFinancialAssets.legendLabel,
          history: _ownedAssetHistory(ownedAsset: ownedAsset, chart: chart),
        ),
      );
    }
    return components;
  }

  /// Walks the live balance back through posted transactions, resetting to
  /// the recorded balance on every day that has a snapshot so market moves
  /// between snapshots do not accumulate.
  static NetWorthComponentHistory _accountHistory({
    required Account account,
    required _AccountRows accountRows,
    required _ChartDays chart,
    required Set<String> includeAccountIds,
  }) {
    if (chart.isEmpty) {
      return NetWorthComponentHistory(
        rawDailyCents: const [],
        firstKnownDayIndex: 0,
      );
    }

    final dayCount = chart.length;
    final postedAmounts = _postedDayAmounts(
      accountRows.transactionsFor(includeAccountIds),
    );
    final List<AccountBalanceSnapshot> snapshots = accountRows.snapshotsFor(
      account.id,
    );
    final snapshotCentsByDay = {
      for (final snapshot in snapshots)
        snapshot.recordedDay: snapshot.balanceCents.toDouble(),
    };
    final CalendarDay knownFrom = [
      ?postedAmounts.earliestDay,
      ?snapshots.firstOrNull?.recordedDay,
      account.balanceAsOf?.calendarDay ?? chart.days.last,
    ].reduce((earliest, day) => day.isBefore(earliest) ? day : earliest);
    final lastDayIndex = dayCount - 1;
    // Live balance always belongs on the last chart day. A same-day
    // afternoon balanceAsOf must not zero the midnight endpoint.
    var firstKnownDayIndex = _firstIndexOnOrAfter(chart.days, knownFrom);
    if (firstKnownDayIndex > lastDayIndex) firstKnownDayIndex = lastDayIndex;

    var balanceCents = account.balanceCents.toDouble();
    final values = List<double>.filled(dayCount, 0);
    for (var dayIndex = lastDayIndex; dayIndex >= 0; dayIndex--) {
      final CalendarDay day = chart.days[dayIndex];
      if (dayIndex < lastDayIndex && day.isBefore(knownFrom)) {
        values[dayIndex] = 0;
        continue;
      }
      if (dayIndex < lastDayIndex) {
        balanceCents = snapshotCentsByDay[day] ?? balanceCents;
      }
      values[dayIndex] = balanceCents;
      balanceCents -= postedAmounts.amountsByDay[day] ?? 0;
    }
    return NetWorthComponentHistory(
      rawDailyCents: values,
      firstKnownDayIndex: firstKnownDayIndex,
    );
  }

  static NetWorthComponentHistory _ownedAssetHistory({
    required OwnedAssetWithValuations ownedAsset,
    required _ChartDays chart,
  }) {
    final rawDailyCents = ownedAsset.dailyCents(chart.days);
    final CalendarDay? firstValuedDay = ownedAsset.firstValuedOn;
    final firstKnownDayIndex = firstValuedDay == null
        ? chart.length
        : _firstIndexOnOrAfter(chart.days, firstValuedDay);
    return NetWorthComponentHistory(
      rawDailyCents: rawDailyCents,
      firstKnownDayIndex: firstKnownDayIndex,
    );
  }

  static _PostedDayAmounts _postedDayAmounts(
    Iterable<BankTransaction> transactions,
  ) {
    final amountsByDay = <CalendarDay, double>{};
    CalendarDay? earliestDay;
    for (final transaction in transactions) {
      final CalendarDay day = transaction.postedDay;
      amountsByDay.update(
        day,
        (prior) => prior + transaction.amountCents,
        ifAbsent: () => transaction.amountCents.toDouble(),
      );
      if (earliestDay == null || day.isBefore(earliestDay)) {
        earliestDay = day;
      }
    }
    return _PostedDayAmounts(
      amountsByDay: amountsByDay,
      earliestDay: earliestDay,
    );
  }

  /// Binary search over the ascending chart days; `chartDays.length` when
  /// every day is before [knownFrom].
  static int _firstIndexOnOrAfter(
    List<CalendarDay> chartDays,
    CalendarDay knownFrom,
  ) {
    var low = 0;
    var high = chartDays.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (chartDays[middle].isBefore(knownFrom)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Signed sum of every component (smoothed per component, so an account
  /// joining mid-chart does not blur the total), except that each day
  /// [importedNetWorthDays] covers takes Empower's total: before this app
  /// recorded balances, its walk-back misses market moves and accounts that
  /// were not linked yet.
  static CategoryTrendSeries? _totalSeries({
    required List<_SignedNetWorthComponent> components,
    required _ChartDays chart,
    required List<ImportedNetWorthDay> importedNetWorthDays,
  }) {
    if (components.isEmpty || chart.isEmpty) return null;
    final dayCount = chart.length;
    final rollingCents = List<double>.filled(dayCount, 0);
    final smoothedCents = List<double>.filled(dayCount, 0);
    for (final component in components) {
      final smoothedDaily = component.history.smoothedDailyCents;
      for (var dayIndex = 0; dayIndex < dayCount; dayIndex++) {
        rollingCents[dayIndex] += component.history.rawDailyCents[dayIndex];
        smoothedCents[dayIndex] += smoothedDaily[dayIndex];
      }
    }
    _replaceWithImportedNetWorth(
      importedNetWorthDays: importedNetWorthDays,
      chartDays: chart.days,
      rollingCents: rollingCents,
      smoothedCents: smoothedCents,
    );
    return _seriesFromPoints(
      id: TrendChartCatalog.netWorthSeriesId,
      name: 'Net worth',
      lineColor: TrendChartCatalog.netWorthLineColor,
      percentileAreaFill: true,
      points: [
        for (var dayIndex = 0; dayIndex < dayCount; dayIndex++)
          CategoryTrendPoint(
            date: chart.dates[dayIndex],
            rollingCents: rollingCents[dayIndex],
            smoothedCents: smoothedCents[dayIndex],
          ),
      ],
    );
  }

  /// Overwrites the chart days Empower covers; that stretch is smoothed on
  /// its own so this app's days after it do not bleed in.
  static void _replaceWithImportedNetWorth({
    required List<ImportedNetWorthDay> importedNetWorthDays,
    required List<CalendarDay> chartDays,
    required List<double> rollingCents,
    required List<double> smoothedCents,
  }) {
    final importedCentsByDay = {
      for (final importedDay in importedNetWorthDays)
        importedDay.day: importedDay.netWorthCents,
    };
    final importedDayIndexes = [
      for (var dayIndex = 0; dayIndex < chartDays.length; dayIndex++)
        if (importedCentsByDay.containsKey(chartDays[dayIndex])) dayIndex,
    ];
    if (importedDayIndexes.isEmpty) return;
    final firstIndex = importedDayIndexes.first;
    final lastIndex = importedDayIndexes.last;
    for (var dayIndex = firstIndex; dayIndex <= lastIndex; dayIndex++) {
      final int? importedCents = importedCentsByDay[chartDays[dayIndex]];
      if (importedCents != null) {
        rollingCents[dayIndex] = importedCents.toDouble();
      }
    }
    final importedSmoothed = CenteredMovingAverage.standard.smoothValues(
      rollingCents.sublist(firstIndex, lastIndex + 1),
    );
    for (var offset = 0; offset < importedSmoothed.length; offset++) {
      smoothedCents[firstIndex + offset] = importedSmoothed[offset];
    }
  }

  static List<CategoryTrendSeries> _breakdownSeries(
    List<_SignedNetWorthComponent> components,
    List<DateTime> chartDates,
  ) {
    final breakdownSeries = <CategoryTrendSeries>[];
    for (final component in components) {
      final built = _seriesFromHistory(
        component: component,
        chartDates: chartDates,
      );
      if (built != null) breakdownSeries.add(built);
    }
    return breakdownSeries;
  }

  static CategoryTrendSeries? _seriesFromHistory({
    required _SignedNetWorthComponent component,
    required List<DateTime> chartDates,
  }) {
    final rawDailyCents = component.history.rawDailyCents;
    final smoothedDailyCents = component.history.smoothedDailyCents;
    return _seriesFromPoints(
      id: component.id,
      name: component.name,
      lineColor: component.lineColor,
      dotted: component.dotted,
      legendGroup: component.legendGroup,
      points: [
        for (var dayIndex = 0; dayIndex < chartDates.length; dayIndex++)
          CategoryTrendPoint(
            date: chartDates[dayIndex],
            rollingCents: _plotCents(
              rawDailyCents[dayIndex],
              plotAbsoluteMagnitude: component.plotAbsoluteMagnitude,
            ),
            smoothedCents: _plotCents(
              smoothedDailyCents[dayIndex],
              plotAbsoluteMagnitude: component.plotAbsoluteMagnitude,
            ),
          ),
      ],
    );
  }

  static double _plotCents(
    double signedCents, {
    required bool plotAbsoluteMagnitude,
  }) {
    return plotAbsoluteMagnitude ? signedCents.abs() : signedCents;
  }

  static CategoryTrendSeries? _seriesFromPoints({
    required String id,
    required String name,
    required Color lineColor,
    required List<CategoryTrendPoint> points,
    bool dotted = false,
    bool percentileAreaFill = false,
    String? legendGroup,
    String? legendCaption,
  }) {
    final built = CategoryTrendSeries(
      id: id,
      name: name,
      lineColor: lineColor,
      dotted: dotted,
      percentileAreaFill: percentileAreaFill,
      legendGroup: legendGroup,
      legendCaption: legendCaption,
      points: points,
    );
    if (!built.hasMeaningfulTrend) return null;
    return built;
  }

  static Set<String> _historyAccountIds(
    Account account,
    List<Account> accounts,
  ) {
    if (account.hasParent) return {account.id};
    return {
      account.id,
      for (final other in accounts)
        if (other.belongsToAccountId == account.id) other.id,
    };
  }

  /// Every local midnight from [firstDay] through [endDay].
  static List<DateTime> _calendarDates(
    CalendarDay firstDay,
    CalendarDay endDay,
  ) {
    final int dayCount = endDay.daysSince(firstDay) + 1;
    if (dayCount <= 0) return [];
    return List.generate(
      dayCount,
      (dayOffset) => firstDay.plusDays(dayOffset).localMidnight,
    );
  }

  /// Accounts with a live balance to walk back from, plus history imports
  /// valued by their imported snapshots (never walked back from \$0).
  static List<Account> _rootAccounts(List<Account> accounts) => [
    for (final account in accounts)
      if (account.countsTowardNetWorthHistory) account,
  ];

  static Map<String, Set<String>> _childIdsByParent(List<Account> accounts) {
    final childIdsByParent = <String, Set<String>>{};
    for (final account in accounts) {
      final parentId = account.belongsToAccountId;
      if (parentId == null) continue;
      childIdsByParent.putIfAbsent(parentId, () => {}).add(account.id);
    }
    return childIdsByParent;
  }

  static List<_KindAccountGroup> _accountsByKind(List<Account> accounts) {
    final byKind = <AccountKind, List<Account>>{};
    for (final account in accounts) {
      byKind.putIfAbsent(account.kind, () => []).add(account);
    }
    final sortedKinds = byKind.keys.toList()
      ..sort(
        (left, right) => left.legendSortOrder.compareTo(right.legendSortOrder),
      );
    return [
      for (final kind in sortedKinds)
        _KindAccountGroup(
          kind: kind,
          accounts: [...byKind[kind]!]
            ..sort(
              (left, right) =>
                  right.balanceCents.abs().compareTo(left.balanceCents.abs()),
            ),
        ),
    ];
  }
}

/// Transactions and recorded balances grouped by account, built once per
/// chart so each account's history reads its own rows instead of filtering
/// every table again.
class _AccountRows({
  required List<BankTransaction> transactions,
  List<AccountBalanceSnapshot> balanceSnapshots = const [],
}) {
  final Map<String, List<BankTransaction>> _transactionsByAccountId =
      _groupedByAccount(transactions, (transaction) => transaction.accountId);

  /// Oldest first within each account.
  final Map<String, List<AccountBalanceSnapshot>> _snapshotsByAccountId =
      _groupedByAccount(balanceSnapshots, (snapshot) => snapshot.accountId)
        ..forEach(
          (_, snapshots) => snapshots.sort(
            (left, right) => left.recordedDay.compareTo(right.recordedDay),
          ),
        );

  /// Oldest first.
  List<AccountBalanceSnapshot> snapshotsFor(String accountId) =>
      _snapshotsByAccountId[accountId] ?? const [];

  Iterable<BankTransaction> transactionsFor(Set<String> accountIds) => [
    for (final accountId in accountIds) ...?_transactionsByAccountId[accountId],
  ];

  static Map<String, List<AccountRow>> _groupedByAccount<AccountRow>(
    List<AccountRow> rows,
    String Function(AccountRow row) accountIdOf,
  ) {
    final byAccountId = <String, List<AccountRow>>{};
    for (final row in rows) {
      byAccountId.putIfAbsent(accountIdOf(row), () => []).add(row);
    }
    return byAccountId;
  }
}

class const _PostedDayAmounts({
  required final Map<CalendarDay, double> amountsByDay,
  final CalendarDay? earliestDay,
});

/// The chart's consecutive days: local midnights for the plotted points and
/// their [CalendarDay]s for every lookup and comparison.
class _ChartDays(final List<DateTime> dates) {
  final List<CalendarDay> days = [for (final date in dates) date.calendarDay];

  int get length => dates.length;
  bool get isEmpty => dates.isEmpty;
}

class const _SignedNetWorthComponent({
  required final String id,
  required final String name,
  required final Color lineColor,
  required final NetWorthComponentHistory history,
  final bool dotted = false,
  final bool plotAbsoluteMagnitude = false,
  final String? legendGroup,
});

class const _KindAccountGroup({
  required final AccountKind kind,
  required final List<Account> accounts,
});
