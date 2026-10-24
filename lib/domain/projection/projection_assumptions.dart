import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/projection/projection_tax_treatment.dart';

/// What the retirement projection assumes about the future. Everything is in
/// today's dollars (real), so returns are real returns.
///
/// Live data seeds take-home, spending, and balances; the two overrides
/// replace the seeded take-home and non-housing spending when set.
class const ProjectionAssumptions({
  final DateTime? birthDate,
  final int retirementAge = 45,
  final int endAge = 95,
  final double realReturnPercent = 6,
  final double inflationPercent = 3.4,

  /// Tax on traditional withdrawals and on 85% of Social Security.
  final double retirementTaxPercent = 22,
  final int socialSecurityMonthlyDollars = 2561,
  final double mortgageRatePercent = 6.5,

  /// Property tax, insurance, HOA, and upkeep once the mortgage is paid off.
  final int housingAfterPayoffMonthlyDollars = 1200,
  final int? takeHomeOverrideAnnualDollars,
  final int? spendingOverrideAnnualDollars,
  final List<int> childBirthYears = const [],
  final Map<String, ProjectionTaxTreatment> taxTreatmentByAccountId = const {},
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
      mortgageRatePercent:
          (json['mortgageRatePercent'] as num?)?.toDouble() ??
          defaults.mortgageRatePercent,
      housingAfterPayoffMonthlyDollars:
          json['housingAfterPayoffMonthlyDollars'] as int? ??
          defaults.housingAfterPayoffMonthlyDollars,
      takeHomeOverrideAnnualDollars:
          json['takeHomeOverrideAnnualDollars'] as int?,
      spendingOverrideAnnualDollars:
          json['spendingOverrideAnnualDollars'] as int?,
      childBirthYears: [
        for (final year in (json['childBirthYears'] as List?) ?? const [])
          year as int,
      ],
      taxTreatmentByAccountId: {
        for (final entry
            in ((json['taxTreatmentByAccountId'] as Map?) ?? const {}).entries)
          entry.key as String: ProjectionTaxTreatment.values.byName(
            entry.value as String,
          ),
      },
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
    'mortgageRatePercent': mortgageRatePercent,
    'housingAfterPayoffMonthlyDollars': housingAfterPayoffMonthlyDollars,
    'takeHomeOverrideAnnualDollars': takeHomeOverrideAnnualDollars,
    'spendingOverrideAnnualDollars': spendingOverrideAnnualDollars,
    'childBirthYears': childBirthYears,
    'taxTreatmentByAccountId': {
      for (final entry in taxTreatmentByAccountId.entries)
        entry.key: entry.value.name,
    },
  };

  /// Applies the keys present in [changes] (JSON shape; `null` clears an
  /// override or the birth date).
  ProjectionAssumptions merged(Map<String, dynamic> changes) =>
      ProjectionAssumptions.fromJson({...toJson(), ...changes});
}
