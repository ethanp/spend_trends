import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/use_cases/simplefin_pull/simplefin_pull_windows.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 4);

  test('a pull 1 day ago fetches one window starting 2 days before it', () {
    final lastPull = now.subtract(const Duration(days: 1));

    final windows = SimpleFinPullWindows.sinceLastPull(
      lastPull: lastPull,
      now: now,
    );

    expect(windows, hasLength(1));
    expect(windows.single.start, lastPull.subtract(const Duration(days: 2)));
    expect(windows.single.end, now);
  });

  test('a gap longer than 44 days is covered end to end by 44-day windows', () {
    final lastPull = now.subtract(const Duration(days: 100));

    final windows = SimpleFinPullWindows.sinceLastPull(
      lastPull: lastPull,
      now: now,
    );

    expect(windows, hasLength(3));
    expect(windows.first.end, now);
    expect(windows.last.start, lastPull.subtract(const Duration(days: 2)));
    for (var index = 0; index < windows.length; index++) {
      final window = windows[index];
      expect(
        window.end.difference(window.start).inDays,
        lessThanOrEqualTo(SimpleFinPullWindows.windowDays),
      );
      if (index > 0) expect(window.end, windows[index - 1].start);
    }
  });

  test('a pull older than full history starts at the full-history span', () {
    final lastPull = now.subtract(const Duration(days: 365 * 5));

    final windows = SimpleFinPullWindows.sinceLastPull(
      lastPull: lastPull,
      now: now,
    );

    expect(
      windows.last.start,
      SimpleFinPullWindows.fullHistory(now).last.start,
    );
  });
}
