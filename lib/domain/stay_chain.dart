import 'package:spend_trends/theme/finance_colors.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Which life-chain timeline a stay belongs to.
enum LifeChainKind({
  required final String emptyHeroCaption,
  required final String currentCaption,
  required final String addCta,
  required final String labelPlaceholder,
  required final String startDateLabel,
  required final IconData icon,

  /// Base Trends band color for this chain (distinct from life-event gold).
  required final Color trendBandColor,
}) {
  housing(
    emptyHeroCaption: 'No housing yet',
    currentCaption: 'Current home',
    addCta: 'Add place',
    labelPlaceholder: 'Place name',
    startDateLabel: 'Moved in',
    icon: Icons.home,
    trendBandColor: FinanceColors.housing,
  ),
  job(
    emptyHeroCaption: 'No job yet',
    currentCaption: 'Current job',
    addCta: 'Add job',
    labelPlaceholder: 'Employer or role',
    startDateLabel: 'Started',
    icon: Icons.work,
    trendBandColor: FinanceColors.job,
  );

  String get screenTitle => nameAsCapitalizedWords;

  /// Mild per-era accent for labels/edges — tiny hue nudge, odd eras slightly darker.
  ///
  /// Lane fills alternate solid vs hatch in the Trends painter (not by brightness).
  Color trendEraAccent(int eraIndex) {
    final base = HSLColor.fromColor(trendBandColor);
    final hueShift = switch (eraIndex % 5) {
      0 => -8.0,
      1 => 0.0,
      2 => 10.0,
      3 => -4.0,
      _ => 5.0,
    };
    final hue = (base.hue + hueShift) % 360.0;
    final shifted = base.withHue(hue < 0 ? hue + 360.0 : hue);
    if (eraIndex.isEven) return shifted.toColor();
    return shifted
        .withLightness((shifted.lightness - 0.04).clamp(0.0, 1.0))
        .toColor();
  }
}

class const ChainStay({
  required final String id,
  required final String label,
  required final DateTime startedOn,
  final String? note,
});

/// One link in a [StayChain] with a computed residence/employment range.
class const ChainStaySegment({
  required final ChainStay stay,
  required final DateTime rangeStart,

  /// Null when this is the open-ended current stay.
  required final DateTime? rangeEnd,
  required final bool isCurrent,
}) {
  String get dateCaption {
    final formatter = DateFormat.yMMMd();
    final startLabel = formatter.format(rangeStart);
    if (isCurrent || rangeEnd == null) return '$startLabel – present';
    return '$startLabel – ${formatter.format(rangeEnd!)}';
  }

  bool intersectsChart({
    required DateTime chartMinDate,
    required DateTime chartMaxDate,
  }) {
    final start = rangeStart.startOfDay;
    final end = (rangeEnd ?? chartMaxDate).startOfDay;
    final minDate = chartMinDate.startOfDay;
    final maxDate = chartMaxDate.startOfDay;
    return !start.isAfter(maxDate) && !end.isBefore(minDate);
  }

  DateTime effectiveEndOn(DateTime chartMaxDate) {
    return (rangeEnd ?? chartMaxDate).startOfDay;
  }
}

class StayChain(List<ChainStay> stays) {
  final List<ChainStaySegment> segments = _segmentsFor(
    [...stays]..sort(
      (firstStay, secondStay) =>
          firstStay.startedOn.compareTo(secondStay.startedOn),
    ),
  );

  bool get isEmpty => segments.isEmpty;

  ChainStaySegment? get current => segments.isEmpty ? null : segments.last;

  ChainStaySegment? get oldest => segments.isEmpty ? null : segments.first;

  static List<ChainStaySegment> _segmentsFor(List<ChainStay> sortedStays) {
    return [
      for (var index = 0; index < sortedStays.length; index++)
        ChainStaySegment(
          stay: sortedStays[index],
          rangeStart: sortedStays[index].startedOn.startOfDay,
          rangeEnd: index + 1 < sortedStays.length
              ? sortedStays[index + 1].startedOn.startOfDay.subtract(
                  const Duration(days: 1),
                )
              : null,
          isCurrent: index == sortedStays.length - 1,
        ),
    ];
  }
}
