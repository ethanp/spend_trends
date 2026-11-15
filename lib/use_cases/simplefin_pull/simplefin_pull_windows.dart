/// SimpleFIN bridge date-window policy (45-day max, overlap for late posts).
class SimpleFinPullWindows._() {
  /// beta-bridge rejects ranges of 45+ days.
  static const windowDays = 44;
  static const fullHistoryDays = 365 * 2;
  static const incrementalOverlapDays = 2;

  static List<SimpleFinDateWindow> fullHistory(DateTime now) =>
      _windowsNewestFirst(
        earliest: now.subtract(const Duration(days: fullHistoryDays)),
        now: now,
      );

  /// Every 44-day window from [sinceLastPullStart] to [now], newest first, so
  /// a gap longer than one bridge window is still fully fetched.
  static List<SimpleFinDateWindow> sinceLastPull({
    required DateTime lastPull,
    required DateTime now,
  }) => _windowsNewestFirst(
    earliest: sinceLastPullStart(lastPull: lastPull, now: now),
    now: now,
  );

  /// 2 days before [lastPull], but never further back than the full-history
  /// span.
  static DateTime sinceLastPullStart({
    required DateTime lastPull,
    required DateTime now,
  }) {
    final overlapStart = lastPull.subtract(
      const Duration(days: incrementalOverlapDays),
    );
    final fullHistoryStart = now.subtract(
      const Duration(days: fullHistoryDays),
    );
    return overlapStart.isBefore(fullHistoryStart)
        ? fullHistoryStart
        : overlapStart;
  }

  static List<SimpleFinDateWindow> _windowsNewestFirst({
    required DateTime earliest,
    required DateTime now,
  }) {
    final windows = <SimpleFinDateWindow>[];
    var windowEnd = now;
    while (windowEnd.isAfter(earliest)) {
      final windowStart = windowEnd.subtract(const Duration(days: windowDays));
      final clampedStart = windowStart.isBefore(earliest)
          ? earliest
          : windowStart;
      windows.add(SimpleFinDateWindow(start: clampedStart, end: windowEnd));
      windowEnd = clampedStart;
    }
    return windows;
  }
}

class const SimpleFinDateWindow({
  required final DateTime start,
  required final DateTime end,
});
