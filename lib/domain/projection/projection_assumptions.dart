import 'dart:convert';
import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/projection/life_event.dart';

/// What the retirement projection assumes about the future. Everything is in
/// today's dollars (real), so returns are real returns.
///
/// Live data seeds take-home, spending, and balances; job, home, and child
/// life events change them from when they apply. The spending override
/// replaces the seeded non-housing spending when set. An assumed move is a
/// home the projection adds on its own, to try a move before it is a life
/// event.
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

  /// The year an assumed move happens; null assumes no move.
  final int? assumedMoveYear,
  final int assumedMovePrice = 600000,
  final int assumedMoveDownPayment = 120000,

  /// On a fixed 30-year mortgage.
  final double assumedMoveMortgageRatePercent = 6,
}) {
  static const settingsId = 'retirement_projection';
  static const assumedMoveEventId = 'assumed-move';
  static const _assumedMoveMortgageYears = 30;

  /// Insurance as a share of price when there is no current home to scale
  /// from.
  static const _insuranceShareOfPriceWithoutHome = 0.009;

  /// The home an assumed move buys, carried like [currentHome] (its tax and
  /// upkeep rates, HOA, escrow; insurance scaled to the new price) and
  /// moved into with the usual move costs; null without an assumed move.
  HomeOwnership? assumedMove({required HomeOwnership? currentHome}) {
    final int? moveYear = assumedMoveYear;
    if (moveYear == null) return null;
    final int downPayment = math.min(assumedMoveDownPayment, assumedMovePrice);
    return HomeOwnership(
      id: assumedMoveEventId,
      title: 'Assumed move',
      startedOn: DateTime(moveYear),
      price: assumedMovePrice,
      downPayment: downPayment,
      mortgage: downPayment == assumedMovePrice
          ? null
          : Mortgage(
              ratePercent: assumedMoveMortgageRatePercent,
              years: _assumedMoveMortgageYears,
              hasEscrow: currentHome?.mortgage?.hasEscrow ?? false,
            ),
      insuranceAnnual: currentHome == null || currentHome.price == 0
          ? (assumedMovePrice * _insuranceShareOfPriceWithoutHome).round()
          : (currentHome.insuranceAnnual * assumedMovePrice / currentHome.price)
                .round(),
      hoaAnnual: currentHome?.hoaAnnual ?? 0,
      maintenancePercent: currentHome?.maintenancePercent ?? 2,
      propertyTaxPercent: currentHome?.propertyTaxPercent ?? 2,
    );
  }

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
      assumedMoveYear: json['assumedMoveYear'] as int?,
      assumedMovePrice:
          json['assumedMovePrice'] as int? ?? defaults.assumedMovePrice,
      assumedMoveDownPayment:
          json['assumedMoveDownPayment'] as int? ??
          defaults.assumedMoveDownPayment,
      assumedMoveMortgageRatePercent:
          (json['assumedMoveMortgageRatePercent'] as num?)?.toDouble() ??
          defaults.assumedMoveMortgageRatePercent,
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
    'assumedMoveYear': assumedMoveYear,
    'assumedMovePrice': assumedMovePrice,
    'assumedMoveDownPayment': assumedMoveDownPayment,
    'assumedMoveMortgageRatePercent': assumedMoveMortgageRatePercent,
  };

  /// Equal when every saved key is: a sync echo of the same row is not a
  /// change.
  @override
  bool operator ==(Object other) =>
      other is ProjectionAssumptions &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  /// Applies the keys present in [changes] (JSON shape; `null` clears the
  /// override, the birth date, or the assumed move).
  ProjectionAssumptions merged(Map<String, dynamic> changes) =>
      ProjectionAssumptions.fromJson({...toJson(), ...changes});
}
