import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';

/// How an account's money is taxed when it is spent, for retirement
/// projections. Inferred from the account unless set on Banks.
enum AccountTaxTreatment({final String? _label}) {
  /// Pre-tax (401(k), traditional / rollover IRA): withdrawals taxed as income.
  traditional(),

  /// Tax-free when qualified (Roth IRA, HSA).
  roth(),

  /// 529 plans: tax-free for school, so they pay the kids' college years
  /// and never fund retirement.
  college(label: 'College (529)'),

  /// Brokerage, crypto, cash, and card balances: gains taxed when sold.
  taxable(),

  /// Loans (the mortgage is modeled with the home) and anything not liquid.
  excluded(label: 'Not counted');

  String get label => _label ?? nameAsCapitalizedWords;

  static AccountTaxTreatment? tryFromStorage(String? value) {
    for (final treatment in values) {
      if (treatment.name == value) return treatment;
    }
    return null;
  }

  /// Best guess from the account's kind and name, used until one is set.
  static AccountTaxTreatment inferredFor(Account account) {
    final name = '${account.displayName} ${account.name}'.toLowerCase();
    return switch (account.kind) {
      AccountKind.loans || AccountKind.nonFinancialAssets => excluded,
      AccountKind.investment when name.contains('529') => college,
      AccountKind.investment when _mentionsAny(name, _rothWords) => roth,
      AccountKind.investment when _mentionsAny(name, _traditionalWords) =>
        traditional,
      _ => taxable,
    };
  }

  static const _rothWords = ['roth', 'hsa'];
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
