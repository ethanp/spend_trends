import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/domain/account_tax_treatment.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/domain/projection/savings_balances.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';
import 'package:spend_trends/features/projections/savings_history.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_card.dart';

final _savingsHistoryProvider = FutureProvider<SavingsHistory>((ref) async {
  final Map<String, Account> accounts = await ref.watch(
    accountsMapProvider.future,
  );
  final List<BankTransaction> transactions = await ref.watch(
    transactionsListProvider.future,
  );
  final List<AccountBalanceSnapshot> balanceSnapshots = await ref.watch(
    accountBalanceSnapshotsProvider.future,
  );
  final List<OwnedAssetWithValuations> ownedAssets = await ref.watch(
    ownedAssetsListProvider.future,
  );
  return SavingsHistory.reconstruct(
    today: DateTime.now(),
    accounts: accounts.values.toList(),
    transactions: transactions,
    balanceSnapshots: balanceSnapshots,
    ownedAssets: ownedAssets,
  );
});

/// Liquid savings by tax type and home equity: actual month by month since
/// Trends history begins, then projected year by year, with today and the
/// planned and earliest retirement ages marked.
class const ProjectionChartCard({
  required final RetirementProjection projection,
}) extends ConsumerWidget {
  static const _chartHeight = 320.0;
  static const _earliestRetirementColor = EColors.success;
  static const _plannedRetirementColor = EColors.warning;
  static const _todayColor = EColors.textMuted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SavingsHistory? savingsHistory = ref
        .watch(_savingsHistoryProvider)
        .asData
        ?.value;
    final List<_DatedSavings> points = [
      for (final savingsOnDay
          in savingsHistory?.inDollarsOf(
                projection.start.today,
                inflationPercent: projection.assumptions.inflationPercent,
              ) ??
              const <SavingsOnDay>[])
        _DatedSavings(date: savingsOnDay.day, savings: savingsOnDay),
      for (final year in projection.years)
        _DatedSavings(date: _dateOfYear(year.year), savings: year),
    ];
    final lines = _lines();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Savings by year (millions, today’s dollars)',
            style: EText.section,
          ),
          const SizedBox(height: ELayout.spaceMd),
          SizedBox(height: _chartHeight, child: _chart(lines, points)),
          const SizedBox(height: ELayout.spaceMd),
          EChartLegend(entries: [for (final line in lines) _legendEntry(line)]),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            'Actual through today (restated at the inflation assumption), '
            'projected after. Gray line: today · gold: planned retirement · '
            'green: earliest. Values at the planned age.',
            style: EText.caption,
          ),
        ],
      ),
    );
  }

  List<_ProjectionLine> _lines() => [
    _ProjectionLine(
      id: 'liquid',
      label: 'Liquid total',
      color: TrendChartCatalog.netWorthLineColor,
      valueOf: (savings) => savings.liquid,
    ),
    for (final treatment in [
      AccountTaxTreatment.taxable,
      AccountTaxTreatment.traditional,
      AccountTaxTreatment.roth,
      AccountTaxTreatment.college,
    ])
      _ProjectionLine(
        id: treatment.name,
        label: treatment.label,
        color: treatment.color,
        valueOf: (savings) => switch (treatment) {
          AccountTaxTreatment.taxable => savings.taxable,
          AccountTaxTreatment.traditional => savings.traditional,
          AccountTaxTreatment.college => savings.college,
          _ => savings.roth,
        },
      ),
    _ProjectionLine(
      id: 'home',
      label: 'Home equity',
      color: OwnedAssetKind.home.lineColor,
      valueOf: (savings) => savings.homeEquity,
      dash: EChartStrokeDash.dotted,
    ),
  ];

  Widget _chart(List<_ProjectionLine> lines, List<_DatedSavings> points) {
    final double peakMillions =
        points
            .map(
              (point) => lines
                  .map((line) => line.valueOf(point.savings))
                  .reduce(math.max),
            )
            .reduce(math.max) /
        1e6;
    return EChart<int>(
      start: points.first.date,
      end: points.last.date,
      valueScale: EChartValueScale.nice(peakMillions, tickSuffix: 'M'),
      series: [
        for (final line in lines)
          EChartSeries<int>.line(
            id: line.id,
            color: line.color,
            dash: line.dash,
            strokeWidth: line.id == 'liquid' ? 2 : 1.2,
            hits: EChartPointHits.ignore,
            points: [
              for (final point in points)
                EChartPoint<int>(
                  date: point.date,
                  value: math.max(0, line.valueOf(point.savings)) / 1e6,
                  id: point.date.millisecondsSinceEpoch,
                ),
            ],
          ),
      ],
      annotations: [
        _YearMarker(date: projection.start.today, color: _todayColor),
        _YearMarker(
          date: _dateAtAge(projection.assumptions.retirementAge),
          color: _plannedRetirementColor,
        ),
        if (projection.earliestRetirementAge != null)
          _YearMarker(
            date: _dateAtAge(projection.earliestRetirementAge!),
            color: _earliestRetirementColor,
          ),
      ],
    );
  }

  /// Each projected year is one year-long step from today.
  DateTime _dateOfYear(int year) =>
      DateTime(year, projection.start.today.month, projection.start.today.day);

  DateTime _dateAtAge(int age) =>
      _dateOfYear(projection.start.today.year + age - projection.currentAge!);

  EChartLegendEntry _legendEntry(_ProjectionLine line) {
    final atRetirement = projection.years
        .where((year) => year.age == projection.assumptions.retirementAge)
        .firstOrNull;
    return EChartLegendEntry(
      swatch: Container(width: 10, height: 10, color: line.color),
      label: line.label,
      value: atRetirement == null
          ? null
          : formatCentsWholeDollars((line.valueOf(atRetirement) * 100).round()),
    );
  }
}

class const _ProjectionLine({
  required final String id,
  required final String label,
  required final Color color,
  required final double Function(SavingsBalances savings) valueOf,
  final EChartStrokeDash dash = EChartStrokeDash.solid,
});

class const _DatedSavings({
  required final DateTime date,
  required final SavingsBalances savings,
});

/// A vertical rule at today or a retirement year.
class _YearMarker({required final DateTime date, required final Color color})
    extends EChartAnnotation {
  @override
  void paint(Canvas canvas, EChartPlot plot) {
    final x = plot.xForDate(date);
    canvas.drawLine(
      Offset(x, plot.top),
      Offset(x, plot.bottom),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
  }
}
