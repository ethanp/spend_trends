import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/accounts/account.dart';

/// Accounts under one institution label for the Banks list.
class const BankInstitutionGroup({
  required final String displayName,
  required final List<Account> accounts,
});

/// Groups / sorts accounts by institution (Copilot last) and measures amounts.
class BankAccountsByInstitution._() {
  static List<BankInstitutionGroup> groups(List<Account> accounts) {
    final byKey = <String, List<Account>>{};
    for (final account in accounts) {
      byKey.putIfAbsent(account.institutionGroupKey, () => []).add(account);
    }
    final sortedKeys = byKey.keys.toList()
      ..sort((left, right) {
        if (left == 'copilot') return 1;
        if (right == 'copilot') return -1;
        final leftName = byKey[left]!.first.institutionDisplayName;
        final rightName = byKey[right]!.first.institutionDisplayName;
        return leftName.compareTo(rightName);
      });
    return [
      for (final key in sortedKeys)
        BankInstitutionGroup(
          displayName: byKey[key]!.first.institutionDisplayName,
          accounts: [...byKey[key]!]..sort(_byAbsoluteBalanceDescending),
        ),
    ];
  }

  static int _byAbsoluteBalanceDescending(Account left, Account right) {
    final byMagnitude = right.balanceCents.abs().compareTo(
      left.balanceCents.abs(),
    );
    if (byMagnitude != 0) return byMagnitude;
    return left.displayName.compareTo(right.displayName);
  }

  static double amountColumnWidth(List<Account> accounts) {
    var widest = 0.0;
    for (final account in accounts) {
      final amountStyle =
          !account.countsTowardNetWorth || account.balanceCents == 0
          ? EText.body.medium.copyWith(color: EColors.textMuted)
          : EText.body.medium.copyWith(fontWeight: FontWeight.w600);
      final width = account.balanceCaption.laidOutWidth(amountStyle);
      if (width > widest) widest = width;
    }
    return widest;
  }
}
