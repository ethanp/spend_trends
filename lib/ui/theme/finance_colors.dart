import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/accounts/account_tax_treatment.dart';

/// Finance product accents on top of ethan_ui chrome tokens.
abstract final class FinanceColors() {
  /// Money / banks CTAs.
  static const accentPrimary = Color(0xFF2A9D8F);

  /// Charts / secondary emphasis.
  static const accentSecondary = Color(0xFFE9C46A);

  /// Housing life-event lane, Housing category, Trends “Spending” series.
  static const housing = Color(0xFFE76F51);

  /// Job life-event lane.
  static const job = EColors.success;

  /// Earliest retirement age: the projection chart marker and FIRE card.
  static const earliestRetirement = EColors.success;

  /// Savings on the three numbers: pay left after the three areas.
  static const savings = Color(0xFF8ECAE6);

  /// Spending excluded from lifestyle costs on the three numbers.
  static const excludedFromLifestyleCosts = Color(0xFFADB5BD);
}

extension ConsciousSpendingAreaColor on ConsciousSpendingArea {
  Color get color => switch (this) {
    ConsciousSpendingArea.fixedCosts => const Color(0xFFB08968),
    ConsciousSpendingArea.investments => const Color(0xFF7D5BA6),
    ConsciousSpendingArea.guiltFree => const Color(0xFFF4A261),
  };
}

extension AccountTaxTreatmentColor on AccountTaxTreatment {
  Color get color => switch (this) {
    AccountTaxTreatment.traditional => const Color(0xFF7D5BA6),
    AccountTaxTreatment.roth => const Color(0xFF2A9D8F),
    AccountTaxTreatment.college => const Color(0xFFE9C46A),
    AccountTaxTreatment.taxable => const Color(0xFF4CC9F0),
    AccountTaxTreatment.excluded => EColors.textMuted,
  };
}
