import 'package:spend_trends/domain/trends/category_trend_distribution.dart';
import 'package:spend_trends/domain/trends/category_trend_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('distributionForSmoothed', () {
    test('returns null for empty points', () {
      expect(distributionForSmoothed(const []), isNull);
    });

    test('returns null when all smoothed values are zero', () {
      expect(
        distributionForSmoothed([
          _point(date: DateTime(2024, 1, 1), smoothedCents: 0),
          _point(date: DateTime(2024, 1, 2), smoothedCents: 0),
        ]),
        isNull,
      );
    });

    test('skips leading zeros and computes stats', () {
      final distribution = distributionForSmoothed([
        _point(date: DateTime(2024, 1, 1), smoothedCents: 0),
        _point(date: DateTime(2024, 1, 2), smoothedCents: 0),
        _point(date: DateTime(2024, 1, 3), smoothedCents: 100),
        _point(date: DateTime(2024, 1, 4), smoothedCents: 300),
        _point(date: DateTime(2024, 1, 5), smoothedCents: 200),
      ]);

      expect(distribution, isNotNull);
      expect(distribution!.minCents, 100);
      expect(distribution.maxCents, 300);
      expect(distribution.averageCents, 200);
      expect(distribution.medianCents, 200);
      expect(distribution.currentCents, 200);
    });

    test('odd-count median is the middle value', () {
      final distribution = distributionForSmoothed([
        _point(date: DateTime(2024, 1, 1), smoothedCents: 10),
        _point(date: DateTime(2024, 1, 2), smoothedCents: 40),
        _point(date: DateTime(2024, 1, 3), smoothedCents: 20),
      ]);

      expect(distribution!.medianCents, 20);
    });

    test('even-count median averages the two middle values', () {
      final distribution = distributionForSmoothed([
        _point(date: DateTime(2024, 1, 1), smoothedCents: 10),
        _point(date: DateTime(2024, 1, 2), smoothedCents: 40),
        _point(date: DateTime(2024, 1, 3), smoothedCents: 20),
        _point(date: DateTime(2024, 1, 4), smoothedCents: 30),
      ]);

      expect(distribution!.medianCents, 25);
      expect(distribution.averageCents, 25);
      expect(distribution.currentCents, 30);
    });

    test('onOrAfter limits the sample window', () {
      final distribution = distributionForSmoothed([
        _point(date: DateTime(2023, 1, 1), smoothedCents: 1000),
        _point(date: DateTime(2024, 6, 1), smoothedCents: 100),
        _point(date: DateTime(2024, 7, 1), smoothedCents: 300),
        _point(date: DateTime(2024, 8, 1), smoothedCents: 200),
      ], onOrAfter: DateTime(2024, 1, 1));

      expect(distribution!.minCents, 100);
      expect(distribution.maxCents, 300);
      expect(distribution.averageCents, 200);
      expect(distribution.currentCents, 200);
    });
  });

  group('distributionPairForSmoothed', () {
    test('splits all-time vs past year', () {
      final pair = distributionPairForSmoothed([
        _point(date: DateTime(2022, 1, 1), smoothedCents: 50),
        _point(date: DateTime(2023, 1, 1), smoothedCents: 900),
        _point(date: DateTime(2024, 6, 1), smoothedCents: 100),
        _point(date: DateTime(2024, 12, 31), smoothedCents: 200),
      ]);

      expect(pair.allTime!.minCents, 50);
      expect(pair.allTime!.maxCents, 900);
      expect(pair.pastYear!.minCents, 100);
      expect(pair.pastYear!.maxCents, 200);
      expect(pair.pastYear!.currentCents, 200);
    });
  });
}

CategoryTrendPoint _point({
  required DateTime date,
  required double smoothedCents,
}) {
  return CategoryTrendPoint(
    date: date,
    rollingCents: smoothedCents,
    smoothedCents: smoothedCents,
  );
}
