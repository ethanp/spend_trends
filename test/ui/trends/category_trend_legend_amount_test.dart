import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:spend_trends/domain/trends/trend_spend_rate.dart';
import 'package:spend_trends/domain/trends/category_trend_point.dart';
import 'package:spend_trends/ui/trends/category_trend_series.dart';
import 'package:spend_trends/ui/trends/category_trend_series_legend.dart';

void main() {
  final checking = CategoryTrendSeries(
    id: 'checking',
    name: 'Checking',
    lineColor: const Color(0xFF00AA00),
    legendGroup: AccountKind.checking.legendLabel,
    points: [
      CategoryTrendPoint(
        date: DateTime(2024, 8, 1),
        rollingCents: 10000,
        smoothedCents: 9000,
      ),
      CategoryTrendPoint(
        date: DateTime(2024, 8, 21),
        rollingCents: 2200000,
        smoothedCents: 1800000,
      ),
      CategoryTrendPoint(
        date: DateTime(2024, 9, 6),
        rollingCents: 2000000,
        smoothedCents: 1970000,
      ),
    ],
  );
  final mortgage = CategoryTrendSeries(
    id: 'loan',
    name: 'Mortgage',
    lineColor: const Color(0xFFAA0000),
    dotted: true,
    legendGroup: AccountKind.loans.legendLabel,
    points: [
      CategoryTrendPoint(
        date: DateTime(2024, 8, 1),
        rollingCents: 400000,
        smoothedCents: 410000,
      ),
      CategoryTrendPoint(
        date: DateTime(2024, 9, 6),
        rollingCents: 528000,
        smoothedCents: 520000,
      ),
    ],
  );

  test('idle level legend uses latest rolling cents', () {
    expect(
      CategoryTrendLegendAmount(
        series: checking,
        valueKind: TrendValueKind.level,
      ).cents,
      2000000,
    );
  });

  test('hovered level legend uses nearest rolling cents', () {
    expect(
      CategoryTrendLegendAmount(
        series: checking,
        valueKind: TrendValueKind.level,
        inspectDate: DateTime(2024, 8, 21),
      ).cents,
      2200000,
    );
  });

  test('idle pace legend uses latest smoothed cents', () {
    expect(
      CategoryTrendLegendAmount(
        series: checking,
        valueKind: TrendValueKind.pace,
      ).cents,
      1970000,
    );
  });

  test('hovered pace legend uses nearest smoothed cents', () {
    expect(
      CategoryTrendLegendAmount(
        series: checking,
        valueKind: TrendValueKind.pace,
        inspectDate: DateTime(2024, 8, 21),
      ).cents,
      1800000,
    );
  });

  test('liability amounts stay signed negative when inspecting', () {
    expect(
      CategoryTrendLegendAmount(
        series: mortgage,
        valueKind: TrendValueKind.level,
      ).cents,
      -528000,
    );
    expect(
      CategoryTrendLegendAmount(
        series: mortgage,
        valueKind: TrendValueKind.level,
        inspectDate: DateTime(2024, 8, 1),
      ).cents,
      -400000,
    );
  });
}
