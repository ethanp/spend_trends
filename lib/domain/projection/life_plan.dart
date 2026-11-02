import 'package:spend_trends/domain/projection/life_event.dart';

/// The life events the projection reads: which job and home apply on a day
/// (the latest-started one wins), and every child.
class LifePlan(List<LifeEvent> lifeEvents) {
  final List<LifeEvent> _latestStartedFirst = [...lifeEvents]
    ..sort((left, right) => right.startedOn.compareTo(left.startedOn));

  late final List<ChildBirth> children = [
    for (final lifeEvent in _latestStartedFirst)
      if (lifeEvent is ChildBirth) lifeEvent,
  ];

  /// Null when no job event applies (the projection then uses live take-home).
  Job? jobOn(DateTime day) => _latestApplying<Job>(day);

  /// Null when no home event applies.
  HomeOwnership? homeOn(DateTime day) => _latestApplying<HomeOwnership>(day);

  /// Yearly cost of every child in [year], today's dollars.
  double childCostsIn(int year) =>
      children.fold(0.0, (total, child) => total + child.costIn(year));

  /// The college-years part of [childCostsIn].
  double collegeCostsIn(int year) =>
      children.fold(0.0, (total, child) => total + child.collegeCostIn(year));

  /// This plan plus [home], which applies from its start like any home
  /// event; the saved life events are untouched.
  LifePlan withHome(HomeOwnership home) =>
      LifePlan([..._latestStartedFirst, home]);

  T? _latestApplying<T extends LifeEvent>(DateTime day) {
    for (final lifeEvent in _latestStartedFirst) {
      if (lifeEvent is T && lifeEvent.appliesOn(day)) return lifeEvent;
    }
    return null;
  }
}
