import 'package:ethan_utils/ethan_utils.dart';

/// What the retirement projection assumes about the future. Everything is in
/// today's dollars (real), so returns are real returns.
///
/// Live data seeds take-home, spending, and balances; job, home, and child
/// life events change them from when they apply. The spending override
/// replaces the seeded non-housing spending when set.
class const ProjectionAssumptions({
  final DateTime? birthDate,
  final int retirementAge = 45,
  final int endAge = 95,
  final double realReturnPercent = 6,
  final double inflationPercent = 3.4,

  /// Tax on traditional withdrawals and on 85% of Social Security.
  final double retirementTaxPercent = 22,
  final int socialSecurityMonthlyDollars = 2561,
  final int? spendingOverrideAnnualDollars,
}) {
  static const settingsId = 'retirement_projection';

  factory fromJson(Map<String, dynamic> json) {
    const defaults = ProjectionAssumptions();
    return ProjectionAssumptions(
      birthDate: switch (json['birthDate']) {
        final String day => DateTime.parse(day),
        _ => null,
      },
      retirementAge: json['retirementAge'] as int? ?? defaults.retirementAge,
      endAge: json['endAge'] as int? ?? defaults.endAge,
      realReturnPercent:
          (json['realReturnPercent'] as num?)?.toDouble() ??
          defaults.realReturnPercent,
      inflationPercent:
          (json['inflationPercent'] as num?)?.toDouble() ??
          defaults.inflationPercent,
      retirementTaxPercent:
          (json['retirementTaxPercent'] as num?)?.toDouble() ??
          defaults.retirementTaxPercent,
      socialSecurityMonthlyDollars:
          json['socialSecurityMonthlyDollars'] as int? ??
          defaults.socialSecurityMonthlyDollars,
      spendingOverrideAnnualDollars:
          json['spendingOverrideAnnualDollars'] as int?,
    );
  }

  Map<String, Object?> toJson() => {
    'birthDate': birthDate?.dayKey,
    'retirementAge': retirementAge,
    'endAge': endAge,
    'realReturnPercent': realReturnPercent,
    'inflationPercent': inflationPercent,
    'retirementTaxPercent': retirementTaxPercent,
    'socialSecurityMonthlyDollars': socialSecurityMonthlyDollars,
    'spendingOverrideAnnualDollars': spendingOverrideAnnualDollars,
  };

  /// Applies the keys present in [changes] (JSON shape; `null` clears the
  /// override or the birth date).
  ProjectionAssumptions merged(Map<String, dynamic> changes) =>
      ProjectionAssumptions.fromJson({...toJson(), ...changes});
}
