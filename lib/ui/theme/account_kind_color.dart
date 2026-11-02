import 'package:spend_trends/domain/accounts/account_kind.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

/// Stable colors for account-kind identity on the net worth chart.
///
/// Each [AccountKind] has a base hue; accounts within a kind share that family
/// with a per-account shade (same pattern as [CategoryColor] group members).
class AccountKindColor._() {
  static Color forKind(AccountKind kind) => switch (kind) {
    AccountKind.checking => const Color(0xFF4CC9F0),
    AccountKind.savings => const Color(0xFF2EC4B6),
    AccountKind.investment => const Color(0xFF9B5DE5),
    AccountKind.nonFinancialAssets => const Color(0xFFF4A261),
    AccountKind.creditCard => const Color(0xFFF72585),
    AccountKind.loans => const Color(0xFFE63946),
    AccountKind.other => const Color(0xFF80ED99),
  };

  static Color forAccount({
    required AccountKind kind,
    required String accountId,
  }) => forKind(kind).shadeKeyedBy(accountId);
}
