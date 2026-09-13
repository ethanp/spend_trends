import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Finance product accents on top of ethan_ui chrome tokens.
abstract final class FinanceColors() {
  /// Money / banks CTAs.
  static const accentPrimary = Color(0xFF2A9D8F);

  /// Charts / secondary emphasis.
  static const accentSecondary = Color(0xFFE9C46A);

  /// Housing chain, Housing category, Trends “Spending” series.
  static const housing = Color(0xFFE76F51);

  /// Job life-chain band on Trends.
  static const job = EColors.success;
}
