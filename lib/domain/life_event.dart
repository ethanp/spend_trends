import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';
import 'package:intl/intl.dart';

/// Something that happened or is planned, shown on Trends charts. Each kind
/// carries what the retirement projection needs to know about it; a
/// [Milestone] carries nothing and only marks the chart.
sealed class const LifeEvent({
  required final String id,
  required final String title,
  required final DateTime startedOn,

  /// Null = open-ended. Equal to [startedOn] = point-in-time. After = closed range.
  final DateTime? endedOn,
  final String? note,
}) {
  LifeEventKind get kind;

  bool get isPoint {
    final end = endedOn;
    if (end == null) return false;
    return end.startOfDay == startedOn.startOfDay;
  }

  bool get isOpenEnded => endedOn == null;

  bool get isClosedRange {
    final end = endedOn;
    if (end == null) return false;
    return end.startOfDay.isAfter(startedOn.startOfDay);
  }

  /// Whether this event's terms apply on [day]: from [startedOn] until
  /// [endedOn]. A point event (a raise, a move-in day) applies from then on.
  bool appliesOn(DateTime day) {
    final target = day.startOfDay;
    if (startedOn.startOfDay.isAfter(target)) return false;
    if (!isClosedRange) return true;
    return !endedOn!.startOfDay.isBefore(target);
  }

  /// End date used for chart clipping (open-ended stretches to [chartMaxDate]).
  DateTime effectiveEndOn(DateTime chartMaxDate) {
    return (endedOn ?? chartMaxDate).startOfDay;
  }

  /// True when the event overlaps the inclusive chart window.
  bool intersectsChart({
    required DateTime chartMinDate,
    required DateTime chartMaxDate,
  }) {
    final start = startedOn.startOfDay;
    final end = effectiveEndOn(chartMaxDate);
    final minDate = chartMinDate.startOfDay;
    final maxDate = chartMaxDate.startOfDay;
    return !start.isAfter(maxDate) && !end.isBefore(minDate);
  }

  String get dateCaption {
    final formatter = DateFormat.yMMMd();
    final startLabel = formatter.format(startedOn);
    if (isPoint) return startLabel;
    if (isOpenEnded) return '$startLabel – present';
    return '$startLabel – ${formatter.format(endedOn!)}';
  }
}

/// Which kind of [LifeEvent] a row holds.
enum LifeEventKind() {
  milestone,
  job,
  home,
  childBirth;

  String get label => nameAsCapitalizedWords;
}

/// A marker on the charts with no effect on the projection.
class const Milestone({
  required super.id,
  required super.title,
  required super.startedOn,
  super.endedOn,
  super.note,
}) extends LifeEvent {
  @override
  LifeEventKind get kind => LifeEventKind.milestone;
}

/// Working somewhere, and what it pays after tax and payroll deductions
/// (dollars a year, today's dollars).
class const Job({
  required super.id,
  required super.title,
  required super.startedOn,
  super.endedOn,
  super.note,
  required final int takeHomeSalaryAnnual,
  required final int takeHomeBonusAnnual,
}) extends LifeEvent {
  @override
  LifeEventKind get kind => LifeEventKind.job;

  int get takeHomeAnnual => takeHomeSalaryAnnual + takeHomeBonusAnnual;
}

/// A fixed-rate home loan's terms.
class const Mortgage({
  required final double ratePercent,
  required final int years,

  /// Property tax and insurance are paid through the servicer rather than
  /// separately; the yearly cost is the same either way.
  required final bool hasEscrow,
}) {
  /// Principal and interest for a year, on a loan of [principal] amortized
  /// monthly over [years].
  double principalAndInterestAnnual(double principal) {
    final monthlyRate = ratePercent / 100 / 12;
    final months = years * 12;
    if (monthlyRate == 0) return principal / years;
    final monthly =
        principal * monthlyRate / (1 - math.pow(1 + monthlyRate, -months));
    return monthly * 12;
  }
}

/// Owning a home: what it cost, how it is financed, and what it costs to
/// keep each year (dollars, today's dollars).
class const HomeOwnership({
  required super.id,
  required super.title,
  required super.startedOn,
  super.endedOn,
  super.note,
  required final int price,
  required final int downPayment,

  /// Null when bought with cash.
  required final Mortgage? mortgage,
  required final int insuranceAnnual,
  required final int hoaAnnual,

  /// Upkeep a year, as a share of the home's value.
  required final double maintenancePercent,

  /// Property tax a year, as a share of the home's value.
  required final double propertyTaxPercent,
}) extends LifeEvent {
  @override
  LifeEventKind get kind => LifeEventKind.home;

  int get loanAmount => mortgage == null ? 0 : price - downPayment;

  /// Tax, insurance, HOA, and upkeep on a home worth [homeValue]; owed with
  /// or without a mortgage.
  double carryingCostAnnual(double homeValue) =>
      propertyTaxAnnual(homeValue) +
      insuranceAnnual +
      hoaAnnual +
      homeValue * maintenancePercent / 100;

  double propertyTaxAnnual(double homeValue) =>
      homeValue * propertyTaxPercent / 100;
}

/// A child born (or due) on [startedOn], and what raising them costs.
class const ChildBirth({
  required super.id,
  required super.title,
  required super.startedOn,
  super.endedOn,
  super.note,
}) extends LifeEvent {
  @override
  LifeEventKind get kind => LifeEventKind.childBirth;

  /// Yearly cost at each age in Sugar Land, today's dollars; 0 before birth.
  /// Housing is left out (the mortgage covers it): center daycare until
  /// Fort Bend ISD kindergarten at 5, then in-state public university.
  double costIn(int year) {
    final childAge = year - startedOn.year;
    if (childAge < 0) return 0;
    if (childAge <= 4) return 22e3;
    if (childAge <= 18) return 17e3;
    if (childAge <= _lastCollegeAge) return _collegeCostAnnual;
    if (childAge <= 26) return 5e3;
    return 1e3;
  }

  static const _lastCollegeAge = 22;
  static const _collegeCostAnnual = 30e3;

  /// The part of [costIn] that a 529 can pay: in-state public university.
  double collegeCostIn(int year) {
    final childAge = year - startedOn.year;
    if (childAge < 19 || childAge > _lastCollegeAge) return 0;
    return _collegeCostAnnual;
  }
}
