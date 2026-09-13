import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/features/trends/category_trend_plot.dart';
import 'package:spend_trends/features/trends/category_trend_point.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/pace_line_samples.dart';

void main() {
  group('CategoryTrendSeries.smoothedCentsAt', () {
    final series = _series([
      _point(DateTime(2024, 1, 1), 100),
      _point(DateTime(2024, 1, 3), 300),
    ]);

    test('clamps before the first date', () {
      expect(series.smoothedCentsAt(DateTime(2023, 12, 31)), 100);
    });

    test('clamps after the last date', () {
      expect(series.smoothedCentsAt(DateTime(2024, 1, 4)), 300);
    });

    test('returns the point value on an exact date', () {
      expect(series.smoothedCentsAt(DateTime(2024, 1, 1)), 100);
      expect(series.smoothedCentsAt(DateTime(2024, 1, 3)), 300);
    });

    test('interpolates between chronological points', () {
      expect(series.smoothedCentsAt(DateTime(2024, 1, 2)), 200);
    });
  });

  group('CategoryTrendSeries.nearestPoint', () {
    final series = _series([
      _point(DateTime(2024, 1, 1), 100),
      _point(DateTime(2024, 1, 4), 400),
      _point(DateTime(2024, 1, 10), 50),
    ]);

    test('returns null when empty', () {
      expect(_series(const []).nearestPoint(DateTime(2024, 1, 1)), isNull);
    });

    test('picks the closer chronological neighbor', () {
      expect(
        series.nearestPoint(DateTime(2024, 1, 2))!.date,
        DateTime(2024, 1, 1),
      );
      expect(
        series.nearestPoint(DateTime(2024, 1, 3))!.date,
        DateTime(2024, 1, 4),
      );
      expect(
        series.nearestPoint(DateTime(2024, 1, 8))!.date,
        DateTime(2024, 1, 10),
      );
    });

    test('prefers the earlier point when equidistant', () {
      expect(
        series.nearestPoint(DateTime(2024, 1, 7))!.date,
        DateTime(2024, 1, 4),
      );
    });
  });

  group('PaceLineSamples.percentileRank', () {
    test('matches the midrank formula on a sorted list', () {
      const sortedValues = [10.0, 20.0, 20.0, 40.0];
      expect(
        PaceLineSamples.percentileRank(sortedValues, 10),
        closeTo(0.125, 1e-9),
      );
      expect(
        PaceLineSamples.percentileRank(sortedValues, 20),
        closeTo(0.5, 1e-9),
      );
      expect(
        PaceLineSamples.percentileRank(sortedValues, 40),
        closeTo(0.875, 1e-9),
      );
      expect(PaceLineSamples.percentileRank(sortedValues, 0), 0);
      expect(PaceLineSamples.percentileRank(sortedValues, 50), 1);
    });

    test('is 0.5 for a single sample', () {
      expect(PaceLineSamples.percentileRank(const [7], 7), 0.5);
    });
  });

  group('PaceLineSamples.alongPlot', () {
    test('emits one sample per plot pixel and matches smoothedCentsAt', () {
      final series = _series([
        _point(DateTime(2024, 1, 1), 100),
        _point(DateTime(2024, 1, 31), 400),
      ], percentileAreaFill: true);
      const plotSize = Size(260, 560);
      final plot = CategoryTrendPlot.from(size: plotSize, seriesList: [series]);
      final samples = PaceLineSamples.alongPlot(series: series, plot: plot);

      var expectedCount = 0;
      for (
        var columnX = plot.chart.left;
        columnX < plot.chart.right;
        columnX += PaceLineSamples.columnWidth
      ) {
        expectedCount++;
      }
      expect(samples.offsets.length, expectedCount);
      expect(samples.percentileRanks.length, expectedCount);

      for (final offset in samples.offsets) {
        final sampleDate = plot.dateForX(offset.dx);
        final expectedY = plot.scale.yForCents(
          series.smoothedCentsAt(sampleDate),
          plot.chart,
        );
        expect(offset.dy, closeTo(expectedY, 0.01));
      }
    });
  });
}

CategoryTrendSeries _series(
  List<CategoryTrendPoint> points, {
  bool percentileAreaFill = false,
}) {
  return CategoryTrendSeries(
    id: 'test',
    name: 'Test',
    lineColor: const Color(0xFF00AA00),
    points: points,
    percentileAreaFill: percentileAreaFill,
  );
}

CategoryTrendPoint _point(DateTime date, double smoothedCents) {
  return CategoryTrendPoint(
    date: date,
    rollingCents: smoothedCents,
    smoothedCents: smoothedCents,
  );
}
