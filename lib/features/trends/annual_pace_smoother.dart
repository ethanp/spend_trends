import 'dart:math' as math;
import 'dart:typed_data';

import 'package:spend_trends/features/trends/category_trend_point.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/hann_annual_pace_kernel.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

/// Inclusive index span where a kernel centered at a day has support.
class const KernelSupportSpan({
  required final int startIndex,
  required final int endIndex,
});

/// Builds annualized `/ yr` pace series with a tapered [HannAnnualPaceKernel].
///
/// Pace at day D is `yearDays ×` weighted mean daily cents under the kernel
/// (renormalized at chart edges). No separate CMA pass — the kernel is the
/// low-pass.
class AnnualPaceSmoother({required final HannAnnualPaceKernel kernel}) {
  static final standard = AnnualPaceSmoother(kernel: HannAnnualPaceKernel());

  /// Calendar-year length used for annualization / trailing-year helpers.
  int get yearDays => kernel.yearDays;

  int get halfWidthDays => kernel.halfWidthDays;

  /// Scale a trailing total up to a full-year pace (budget month rows, etc.).
  static double annualizeTrailingTotal({
    required double windowTotalCents,
    required int observedDays,
    int yearDays = HannAnnualPaceKernel.defaultYearDays,
  }) {
    if (observedDays <= 0) return 0;
    if (observedDays >= yearDays) return windowTotalCents;
    return windowTotalCents * yearDays / observedDays;
  }

  CategoryTrendSeries seriesFromDailyMap({
    required String id,
    required String name,
    required Color lineColor,
    required Map<CalendarDay, double> dailyCents,
    required List<DateTime> chartDates,
    required DateTime historyFloor,
    bool dotted = false,
    bool guide = false,
    bool percentileAreaFill = false,
    String? legendCaption,
    String? memberOfGroupSeriesId,
  }) {
    return CategoryTrendSeries(
      id: id,
      name: name,
      lineColor: lineColor,
      dotted: dotted,
      guide: guide,
      percentileAreaFill: percentileAreaFill,
      legendCaption: legendCaption,
      memberOfGroupSeriesId: memberOfGroupSeriesId,
      points: pointsFromDailyMap(
        chartDates: chartDates,
        dailyCents: dailyCents,
        historyFloor: historyFloor,
      ),
    );
  }

  /// One point per chart day. Days before [historyFloor] are 0; every other
  /// day is the kernel-weighted mean of the daily cents around it, annualized.
  ///
  /// Only days with spend contribute, so a sparse category costs
  /// `days × its spend days in the window`, not `days × support`.
  List<CategoryTrendPoint> pointsFromDailyMap({
    required List<DateTime> chartDates,
    required Map<CalendarDay, double> dailyCents,
    required DateTime historyFloor,
  }) {
    if (chartDates.isEmpty) return const [];

    final dayCount = chartDates.length;
    final lastDayIndex = dayCount - 1;
    final dailyByIndex = Float64List(dayCount);
    final spendDayIndexes = <int>[];
    for (var dayIndex = 0; dayIndex < dayCount; dayIndex++) {
      final cents = dailyCents[chartDates[dayIndex].calendarDay];
      if (cents == null || cents == 0) continue;
      dailyByIndex[dayIndex] = cents;
      spendDayIndexes.add(dayIndex);
    }

    var historyStartIndex = 0;
    while (historyStartIndex < dayCount &&
        chartDates[historyStartIndex].isBefore(historyFloor)) {
      historyStartIndex++;
    }

    final points = <CategoryTrendPoint>[];
    for (var dayIndex = 0; dayIndex < historyStartIndex; dayIndex++) {
      points.add(
        CategoryTrendPoint(
          date: chartDates[dayIndex],
          rollingCents: 0,
          smoothedCents: 0,
        ),
      );
    }

    var firstSpendDayInWindow = 0;
    for (
      var centerIndex = historyStartIndex;
      centerIndex <= lastDayIndex;
      centerIndex++
    ) {
      final windowStart = math.max(
        historyStartIndex,
        centerIndex - kernel.halfWidthDays,
      );
      final windowEnd = math.min(
        lastDayIndex,
        centerIndex + kernel.halfWidthDays,
      );
      while (firstSpendDayInWindow < spendDayIndexes.length &&
          spendDayIndexes[firstSpendDayInWindow] < windowStart) {
        firstSpendDayInWindow++;
      }

      var weightedCents = 0.0;
      for (
        var spendDay = firstSpendDayInWindow;
        spendDay < spendDayIndexes.length;
        spendDay++
      ) {
        final dayIndex = spendDayIndexes[spendDay];
        if (dayIndex > windowEnd) break;
        weightedCents +=
            kernel.rawWeight(dayIndex - centerIndex) * dailyByIndex[dayIndex];
      }

      final weightSum = kernel.weightSumAt(
        centerIndex: centerIndex,
        historyStartIndex: historyStartIndex,
        lastDayIndex: lastDayIndex,
      );
      final paceCents = weightSum <= 0
          ? 0.0
          : weightedCents / weightSum * kernel.yearDays;
      points.add(
        CategoryTrendPoint(
          date: chartDates[centerIndex],
          rollingCents: paceCents,
          smoothedCents: paceCents,
        ),
      );
    }
    return points;
  }

  /// How much an impulse of [amountCents] on [impulseIndex] adds to pace at
  /// [tapIndex] (same kernel + edge renorm as [pointsFromDailyMap]).
  double impulseContributionCents({
    required double amountCents,
    required int impulseIndex,
    required int tapIndex,
    required int historyStartIndex,
    required int lastDayIndex,
  }) {
    return kernel.normalizedWeight(
          centerIndex: tapIndex,
          dayIndex: impulseIndex,
          historyStartIndex: historyStartIndex,
          lastDayIndex: lastDayIndex,
        ) *
        amountCents *
        kernel.yearDays;
  }

  /// Inclusive day span where the kernel at [centerIndex] has support.
  KernelSupportSpan supportSpan({
    required int centerIndex,
    required int historyStartIndex,
    required int lastDayIndex,
  }) {
    return KernelSupportSpan(
      startIndex: math.max(
        historyStartIndex,
        centerIndex - kernel.halfWidthDays,
      ),
      endIndex: math.min(lastDayIndex, centerIndex + kernel.halfWidthDays),
    );
  }
}
