import 'package:ethan_utils/ethan_utils.dart';

/// One ordinary-income bracket: [ratePercent] on taxable income up to [top]
/// (the last bracket has no top).
class const IncomeTaxBracket({
  required final int ratePercent,
  final double top = double.infinity,
});

/// How the household files its federal return, with that status's 2026
/// numbers (IRS Rev. Proc. 2025-32). Brackets, the standard deduction, and
/// the capital-gains bands are indexed to inflation, so they hold still in
/// today's dollars. The Social Security thresholds are set in law and never
/// indexed.
enum FilingStatus({
  required final double standardDeduction,

  /// Added to [standardDeduction] once the filers are 65.
  required final double extraDeductionAtSixtyFive,
  required final int adultCount,

  /// Additional Medicare tax applies to wages over this; nominal dollars.
  required final double additionalMedicareTaxWagesOver,
  required final List<IncomeTaxBracket> ordinaryBrackets,

  /// Long-term gains are taxed 0% while taxable income stays under this.
  required final double zeroRateGainsTop,

  /// ...and 15% under this; 20% above.
  required final double fifteenRateGainsTop,

  /// Provisional income over this makes up to half of Social Security
  /// taxable; nominal dollars.
  required final double socialSecurityBaseAmount,

  /// Provisional income over this makes up to 85% taxable; nominal dollars.
  required final double socialSecurityAdjustedBaseAmount,
}) {
  single(
    standardDeduction: 16100,
    extraDeductionAtSixtyFive: 2050,
    adultCount: 1,
    additionalMedicareTaxWagesOver: 200000,
    ordinaryBrackets: [
      IncomeTaxBracket(ratePercent: 10, top: 12400),
      IncomeTaxBracket(ratePercent: 12, top: 50400),
      IncomeTaxBracket(ratePercent: 22, top: 105700),
      IncomeTaxBracket(ratePercent: 24, top: 201775),
      IncomeTaxBracket(ratePercent: 32, top: 256225),
      IncomeTaxBracket(ratePercent: 35, top: 640600),
      IncomeTaxBracket(ratePercent: 37),
    ],
    zeroRateGainsTop: 49450,
    fifteenRateGainsTop: 545500,
    socialSecurityBaseAmount: 25000,
    socialSecurityAdjustedBaseAmount: 34000,
  ),
  marriedFilingJointly(
    standardDeduction: 32200,
    extraDeductionAtSixtyFive: 3300,
    adultCount: 2,
    additionalMedicareTaxWagesOver: 250000,
    ordinaryBrackets: [
      IncomeTaxBracket(ratePercent: 10, top: 24800),
      IncomeTaxBracket(ratePercent: 12, top: 100800),
      IncomeTaxBracket(ratePercent: 22, top: 211400),
      IncomeTaxBracket(ratePercent: 24, top: 403550),
      IncomeTaxBracket(ratePercent: 32, top: 512450),
      IncomeTaxBracket(ratePercent: 35, top: 768700),
      IncomeTaxBracket(ratePercent: 37),
    ],
    zeroRateGainsTop: 98900,
    fifteenRateGainsTop: 613700,
    socialSecurityBaseAmount: 32000,
    socialSecurityAdjustedBaseAmount: 44000,
  );

  String get label => nameAsCapitalizedWords;

  /// Rates a bracket can be filled to: every bracket that has a top.
  List<int> get fillableBracketPercents => [
    for (final bracket in ordinaryBrackets)
      if (bracket.top.isFinite) bracket.ratePercent,
  ];

  /// The top of the bracket taxed at [ratePercent].
  double topOfBracket(int ratePercent) => ordinaryBrackets
      .firstWhere(
        (bracket) => bracket.ratePercent == ratePercent,
        orElse: () =>
            throw ArgumentError('No $ratePercent% bracket for $name.'),
      )
      .top;

  static FilingStatus fromStorage(String? value) =>
      values.where((status) => status.name == value).firstOrNull ?? single;
}
