import 'dart:convert';
import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/taxes/filing_status.dart';

/// What the retirement projection assumes about the future. Everything is in
/// today's dollars (real), so returns are real returns.
///
/// Live data seeds take-home, spending, and balances; job, home, and child
/// life events change them from when they apply. The spending override
/// replaces the seeded non-housing spending when set. An assumed move is a
/// home the projection adds on its own, to try a move before it is a life
/// event.
///
/// Taxes follow the federal return for [filingStatus] (Texas has no state
/// income tax). Accounts with no recorded tax basis assume the share of
/// taxable that is cost and of Roth that is contributions. A Roth conversion bracket fills ordinary income to the top of
/// that bracket each retired year, converting what spending does not use.
class const ProjectionAssumptions({
  final DateTime? birthDate,
  final int retirementAge = 45,
  final int endAge = 95,
  final double realReturnPercent = 6,
  final double inflationPercent = 3.4,
  final FilingStatus filingStatus = FilingStatus.single,

  /// Null: traditional money leaves only when spending needs it or a
  /// required distribution takes it.
  final int? rothConversionBracketPercent,
  final int taxableCostPercent = 60,
  final int rothContributionsPercent = 50,

  /// The benchmark (second-lowest silver) marketplace plan for one adult
  /// your age today, before any credit; it is age-rated from there.
  final int marketplacePremiumMonthlyDollars = 500,
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
      filingStatus: FilingStatus.fromStorage(json['filingStatus'] as String?),
      rothConversionBracketPercent:
          json['rothConversionBracketPercent'] as int?,
      taxableCostPercent:
          json['taxableCostPercent'] as int? ?? defaults.taxableCostPercent,
      rothContributionsPercent:
          json['rothContributionsPercent'] as int? ??
          defaults.rothContributionsPercent,
      marketplacePremiumMonthlyDollars:
          json['marketplacePremiumMonthlyDollars'] as int? ??
          defaults.marketplacePremiumMonthlyDollars,
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
    'filingStatus': filingStatus.name,
    'rothConversionBracketPercent': rothConversionBracketPercent,
    'taxableCostPercent': taxableCostPercent,
    'rothContributionsPercent': rothContributionsPercent,
    'marketplacePremiumMonthlyDollars': marketplacePremiumMonthlyDollars,
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
  ProjectionAssumptions merged(Map<String, dynamic> changes) {
    final merged = ProjectionAssumptions.fromJson({...toJson(), ...changes});
    final int? bracketPercent = merged.rothConversionBracketPercent;
    if (bracketPercent != null &&
        !merged.filingStatus.fillableBracketPercents.contains(bracketPercent)) {
      throw ArgumentError(
        'rothConversionBracketPercent must be one of '
        '${merged.filingStatus.fillableBracketPercents} or null.',
      );
    }
    return merged;
  }
}
