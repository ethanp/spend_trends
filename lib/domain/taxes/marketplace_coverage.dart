import 'dart:math' as math;

/// A year of ACA marketplace coverage for the household: who is covered
/// and the benchmark (second-lowest silver) premium before any credit.
class const MarketplaceCoverage({
  required final int householdSize,
  required final double benchmarkPremiumAnnual,
}) {
  /// HHS poverty guideline (48 states, 2025, which prices 2026 coverage);
  /// indexed, so it holds still in today's dollars.
  static const _povertyLineFirstPerson = 15650.0;
  static const _povertyLinePerAddedPerson = 5500.0;

  /// The credit reaches no further than 400% of the poverty line (the
  /// enhanced credits that lifted this ended with 2025). Below 100% there
  /// is none either: Texas did not expand Medicaid.
  static const _creditFromPovertyRatio = 1.0;
  static const _creditUntilPovertyRatio = 4.0;

  /// Share of income the household pays for the benchmark plan, by
  /// poverty ratio (Rev. Proc. 2025-25), interpolated within each band.
  static const _expectedContributionBands = [
    _ContributionBand(
      fromRatio: 1.00,
      toRatio: 1.33,
      fromShare: 0.0210,
      toShare: 0.0210,
    ),
    _ContributionBand(
      fromRatio: 1.33,
      toRatio: 1.50,
      fromShare: 0.0314,
      toShare: 0.0419,
    ),
    _ContributionBand(
      fromRatio: 1.50,
      toRatio: 2.00,
      fromShare: 0.0419,
      toShare: 0.0660,
    ),
    _ContributionBand(
      fromRatio: 2.00,
      toRatio: 2.50,
      fromShare: 0.0660,
      toShare: 0.0844,
    ),
    _ContributionBand(
      fromRatio: 2.50,
      toRatio: 3.00,
      fromShare: 0.0844,
      toShare: 0.0996,
    ),
    _ContributionBand(
      fromRatio: 3.00,
      toRatio: 4.00,
      fromShare: 0.0996,
      toShare: 0.0996,
    ),
  ];

  double get povertyLine =>
      _povertyLineFirstPerson +
      _povertyLinePerAddedPerson * (householdSize - 1);

  /// The highest modified AGI that still gets a credit.
  double get creditIncomeLimit => povertyLine * _creditUntilPovertyRatio;

  /// The premium tax credit at [modifiedAgi] (AGI plus untaxed Social
  /// Security), assuming the benchmark plan is bought.
  double premiumTaxCreditAt(double modifiedAgi) {
    final double povertyRatio = modifiedAgi / povertyLine;
    if (povertyRatio < _creditFromPovertyRatio ||
        povertyRatio > _creditUntilPovertyRatio) {
      return 0;
    }
    final _ContributionBand band = _expectedContributionBands.lastWhere(
      (band) => povertyRatio >= band.fromRatio,
    );
    return math.max(
      0,
      benchmarkPremiumAnnual - band.shareAt(povertyRatio) * modifiedAgi,
    );
  }
}

class const _ContributionBand({
  required final double fromRatio,
  required final double toRatio,
  required final double fromShare,
  required final double toShare,
}) {
  double shareAt(double povertyRatio) =>
      fromShare +
      (toShare - fromShare) *
          ((povertyRatio - fromRatio) / (toRatio - fromRatio)).clamp(0, 1);
}

/// Marketplace premiums by age: the federal default age curve rates an
/// adult's premium against a 21-year-old's; children under 15 pay the flat
/// child rate.
abstract final class MarketplacePremiums() {
  static const _childRate = 0.765;

  /// Ages 21 through 64; 64 and older pay the age-64 rate.
  static const _adultRateFrom21 = [
    1.000, 1.000, 1.000, 1.000, 1.004, 1.024, 1.048, 1.087, 1.119, 1.135, //
    1.159, 1.183, 1.198, 1.214, 1.222, 1.230, 1.238, 1.246, 1.262, 1.278, //
    1.302, 1.325, 1.357, 1.397, 1.444, 1.500, 1.563, 1.635, 1.706, 1.786, //
    1.865, 1.952, 2.040, 2.135, 2.230, 2.333, 2.437, 2.548, 2.603, 2.714, //
    2.810, 2.873, 2.952, 3.000,
  ];

  /// An adult's benchmark at [age], from what one costs at [knownAge].
  static double adultPremiumAt(
    int age, {
    required double knownPremium,
    required int knownAge,
  }) => knownPremium * _adultRateAt(age) / _adultRateAt(knownAge);

  /// A child's benchmark, from an adult's at [knownAge].
  static double childPremium({
    required double knownPremium,
    required int knownAge,
  }) => knownPremium * _childRate / _adultRateAt(knownAge);

  static double _adultRateAt(int age) =>
      _adultRateFrom21[(age - 21).clamp(0, _adultRateFrom21.length - 1)];
}
