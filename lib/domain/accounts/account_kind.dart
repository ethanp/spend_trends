import 'package:spend_trends/domain/accounts/account.dart';
import 'package:ethan_utils/ethan_utils.dart';

/// Fixed account classes for Trends / net-worth legend grouping.
///
/// SimpleFIN does not send a type; we classify from account + institution names.
enum AccountKind({final String? _legendLabel}) {
  checking(),
  savings(),
  investment(),
  nonFinancialAssets(legendLabel: 'Non-financial assets'),
  creditCard(legendLabel: 'Credit cards'),
  loans(),
  other();

  /// Legend section header.
  String get legendLabel => _legendLabel ?? nameAsCapitalizedWords;

  /// Assets first, then credit / loans, then leftover.
  int get legendSortOrder => index;

  String get storageValue => name;

  static AccountKind? tryFromStorage(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    for (final kind in AccountKind.values) {
      if (kind.name == trimmed) return kind;
    }
    return null;
  }
}

/// Maps an [Account] onto [AccountKind] via name / institution heuristics.
class AccountKindClassifier._() {
  static AccountKind classify(Account account) {
    final haystack = _haystackFor(account);

    // Loans before credit cards so "margin loan" is not a card.
    if (_matchesLoan(haystack, account)) {
      return AccountKind.loans;
    }
    if (_matchesCreditCard(haystack)) {
      return AccountKind.creditCard;
    }
    if (_matchesInvestment(haystack, account)) {
      return AccountKind.investment;
    }
    if (_matchesNonFinancialAsset(haystack)) {
      return AccountKind.nonFinancialAssets;
    }
    if (_matchesChecking(haystack)) {
      return AccountKind.checking;
    }
    if (_matchesSavings(haystack)) {
      return AccountKind.savings;
    }
    return AccountKind.other;
  }

  static String _haystackFor(Account account) {
    return [
      account.displayName,
      account.name,
      account.connName ?? '',
    ].join(' ').toLowerCase();
  }

  static bool _matchesInvestment(String haystack, Account account) {
    if (_containsAny(haystack, const [
          '529',
          '401k',
          '401(k)',
          '403b',
          '403(b)',
          'roth',
          'hsa',
          'sep ira',
          'sep-ira',
          'traditional ira',
          'rollover ira',
          'brokerage',
          'investment',
          'taxable',
          'brokerage account',
          'individual',
          'joint brokerage',
        ]) ||
        _containsToken(haystack, 'ira')) {
      return true;
    }
    // M1 / similar investing apps: positive "Account" balances are portfolios.
    if (account.balanceCents >= 0 && _containsToken(haystack, 'm1')) {
      return true;
    }
    return false;
  }

  static bool _matchesCreditCard(String haystack) {
    return _containsAny(haystack, const [
          'credit card',
          'creditcard',
          'visa',
          'mastercard',
          'american express',
          'amex',
          'sapphire',
          'freedom',
          'reserve',
          'ink business',
          'double cash',
          'venture',
          'quicksilver',
          'platinum card',
          'gold card',
        ]) ||
        (_containsToken(haystack, 'card') &&
            !_containsAny(haystack, const ['gift card', 'debit card']));
  }

  static bool _matchesLoan(String haystack, Account account) {
    if (_containsAny(haystack, const [
      'mortgage',
      'margin',
      'heloc',
      'auto loan',
      'car loan',
      'student loan',
      'personal loan',
      'home loan',
    ])) {
      return true;
    }
    if (_containsToken(haystack, 'loan')) return true;
    // M1 margin lines are often just "Account" with a negative balance.
    if (account.balanceCents < 0 && _containsToken(haystack, 'm1')) {
      return true;
    }
    return false;
  }

  static bool _matchesNonFinancialAsset(String haystack) {
    return _containsAny(haystack, const [
      'non-financial',
      'nonfinancial',
      'real estate',
      'home value',
      'house value',
      'vehicle',
      'car value',
      'auto asset',
    ]);
  }

  static bool _matchesChecking(String haystack) {
    return _containsAny(haystack, const [
      'checking',
      'spend account',
      'spending account',
    ]);
  }

  static bool _matchesSavings(String haystack) {
    return _containsAny(haystack, const [
      'savings',
      'saving',
      'money market',
      'hysa',
      'high yield',
    ]);
  }

  static bool _containsAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }

  static bool _containsToken(String haystack, String token) {
    final padded = ' ${haystack.replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
    return padded.contains(' $token ');
  }
}
