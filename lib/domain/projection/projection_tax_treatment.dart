import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';

/// How a projection taxes an account's money when it is spent.
enum ProjectionTaxTreatment({final String? _label}) {
  /// Pre-tax (401(k), traditional / rollover IRA): withdrawals taxed as income.
  traditional(),

  /// Tax-free when qualified (Roth IRA, HSA, 529).
  roth(),

  /// Brokerage, crypto, cash, and card balances: gains taxed when sold.
  taxable(),

  /// Loans (the mortgage is modeled with the home) and anything not liquid.
  excluded(label: 'Not counted');

  String get label => _label ?? nameAsCapitalizedWords;

  /// Best guess from the account's kind and name; a projection setting can
  /// override it per account.
  static ProjectionTaxTreatment inferredFor(Account account) {
    final name = '${account.displayName} ${account.name}'.toLowerCase();
    return switch (account.kind) {
      AccountKind.loans || AccountKind.nonFinancialAssets => excluded,
      AccountKind.investment when _mentionsAny(name, _rothWords) => roth,
      AccountKind.investment when _mentionsAny(name, _traditionalWords) =>
        traditional,
      _ => taxable,
    };
  }

  static const _rothWords = ['roth', 'hsa', '529'];
  static const _traditionalWords = [
    '401(k)',
    '401k',
    '403(b)',
    '403b',
    'traditional',
    'rollover',
    'sep ira',
    ' ira',
  ];

  static bool _mentionsAny(String text, List<String> words) =>
      words.any(text.contains);
}
