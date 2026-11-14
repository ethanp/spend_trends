/// When retirement-account money can be reached and when it must leave.
abstract final class RetirementAccountRules() {
  /// Born 1960 or later: required distributions start the year you turn 75.
  static const requiredDistributionsFromAge = 75;

  /// A conversion's amount comes out of a Roth penalty-free once five tax
  /// years have started, counting the conversion's own year.
  static const rothConversionSeasoningYears = 5;

  /// The day 59½ is reached: traditional money and Roth earnings come out
  /// without the 10% penalty from then on.
  static DateTime penaltyFreeFrom(DateTime birthDate) =>
      DateTime(birthDate.year + 59, birthDate.month + 6, birthDate.day);

  /// The year's required distribution from a traditional balance (IRS
  /// Uniform Lifetime Table, 2022 onward); 0 before the starting age.
  static double requiredDistributionAt(int age, double traditional) {
    if (age < requiredDistributionsFromAge || traditional <= 0) return 0;
    final int tableIndex = age - requiredDistributionsFromAge;
    final double lifeExpectancy = tableIndex < _uniformLifetimeFrom75.length
        ? _uniformLifetimeFrom75[tableIndex]
        : _uniformLifetimeFrom75.last;
    return traditional / lifeExpectancy;
  }

  /// Distribution periods for ages 75 through 110.
  static const _uniformLifetimeFrom75 = [
    24.6, 23.7, 22.9, 22.0, 21.1, 20.2, 19.4, 18.5, 17.7, 16.8, //
    16.0, 15.2, 14.4, 13.7, 12.9, 12.2, 11.5, 10.8, 10.1, 9.5, //
    8.9, 8.4, 7.8, 7.3, 6.8, 6.4, 6.0, 5.6, 5.2, 4.9, //
    4.6, 4.3, 4.1, 3.9, 3.7, 3.5,
  ];
}
