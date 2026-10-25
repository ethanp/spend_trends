import 'package:spend_trends/domain/life_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LifeEvent kinds', () {
    test('point when endedOn equals startedOn', () {
      final event = Milestone(
        id: '1',
        title: 'Bought car',
        startedOn: DateTime(2024, 3, 15),
        endedOn: DateTime(2024, 3, 15),
      );
      expect(event.isPoint, isTrue);
      expect(event.isOpenEnded, isFalse);
      expect(event.isClosedRange, isFalse);
      expect(event.dateCaption, 'Mar 15, 2024');
    });

    test('open-ended when endedOn is null', () {
      final event = Milestone(
        id: '2',
        title: 'Current job',
        startedOn: DateTime(2022, 1, 1),
      );
      expect(event.isOpenEnded, isTrue);
      expect(event.isPoint, isFalse);
      expect(event.isClosedRange, isFalse);
      expect(event.dateCaption, 'Jan 1, 2022 – present');
      expect(event.effectiveEndOn(DateTime(2025, 6, 1)), DateTime(2025, 6, 1));
    });

    test('closed range when endedOn is after startedOn', () {
      final event = Milestone(
        id: '3',
        title: 'Lived in house',
        startedOn: DateTime(2019, 6, 1),
        endedOn: DateTime(2022, 8, 15),
      );
      expect(event.isClosedRange, isTrue);
      expect(event.isPoint, isFalse);
      expect(event.isOpenEnded, isFalse);
      expect(event.dateCaption, 'Jun 1, 2019 – Aug 15, 2022');
    });
  });

  group('LifeEvent.intersectsChart', () {
    final chartMin = DateTime(2023, 1, 1);
    final chartMax = DateTime(2024, 12, 31);

    test('point inside window', () {
      final event = Milestone(
        id: '1',
        title: 'Move',
        startedOn: DateTime(2023, 6, 1),
        endedOn: DateTime(2023, 6, 1),
      );
      expect(
        event.intersectsChart(chartMinDate: chartMin, chartMaxDate: chartMax),
        isTrue,
      );
    });

    test('point outside window', () {
      final event = Milestone(
        id: '1',
        title: 'Move',
        startedOn: DateTime(2022, 6, 1),
        endedOn: DateTime(2022, 6, 1),
      );
      expect(
        event.intersectsChart(chartMinDate: chartMin, chartMaxDate: chartMax),
        isFalse,
      );
    });

    test('closed range overlapping window start', () {
      final event = Milestone(
        id: '1',
        title: 'House',
        startedOn: DateTime(2022, 1, 1),
        endedOn: DateTime(2023, 6, 1),
      );
      expect(
        event.intersectsChart(chartMinDate: chartMin, chartMaxDate: chartMax),
        isTrue,
      );
    });

    test('closed range entirely before window', () {
      final event = Milestone(
        id: '1',
        title: 'House',
        startedOn: DateTime(2020, 1, 1),
        endedOn: DateTime(2022, 12, 31),
      );
      expect(
        event.intersectsChart(chartMinDate: chartMin, chartMaxDate: chartMax),
        isFalse,
      );
    });

    test('open-ended started before window still intersects', () {
      final event = Milestone(
        id: '1',
        title: 'Job',
        startedOn: DateTime(2020, 1, 1),
      );
      expect(
        event.intersectsChart(chartMinDate: chartMin, chartMaxDate: chartMax),
        isTrue,
      );
    });

    test('open-ended starting after window does not intersect', () {
      final event = Milestone(
        id: '1',
        title: 'Job',
        startedOn: DateTime(2025, 1, 1),
      );
      expect(
        event.intersectsChart(chartMinDate: chartMin, chartMaxDate: chartMax),
        isFalse,
      );
    });
  });
}
