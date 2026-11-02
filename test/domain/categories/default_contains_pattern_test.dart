import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/categories/default_contains_pattern.dart';

void main() {
  test('uses the full merchant lowercased', () {
    expect(
      defaultContainsPattern(
        normalizedMerchant: 'Margin on Current portfolio Charles Schwab',
        rawDescription: '',
      ),
      'margin on current portfolio charles schwab',
    );
  });

  test('keeps direction words like transfer and deposit', () {
    expect(
      defaultContainsPattern(
        normalizedMerchant: 'TRANSFER FUNDS TO SCHWAB BANK',
        rawDescription: '',
      ),
      'transfer funds to schwab bank',
    );
  });

  test('falls back to raw description when merchant is empty', () {
    expect(
      defaultContainsPattern(
        normalizedMerchant: '',
        rawDescription: 'ACH Payment to Utilities',
      ),
      'ach payment to utilities',
    );
  });
}
