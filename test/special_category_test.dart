import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpecialCategory ids', () {
    test('are stable built-in ids', () {
      expect(SpecialCategory.housing.id, 'cat_housing');
      expect(SpecialCategory.income.id, 'cat_income');
      expect(SpecialCategory.transfer.id, 'cat_transfer');
      expect(SpecialCategory.investments.id, 'cat_investments');
      expect(SpecialCategory.isReservedName('Housing'), isTrue);
      expect(SpecialCategory.isReservedName('Income'), isTrue);
      expect(SpecialCategory.isReservedName('Investments'), isTrue);
      expect(SpecialCategory.isReservedName('Groceries'), isFalse);
    });

    test('flow ids exclude housing and include income-like plus transfer', () {
      expect(SpecialCategory.isFlowId(SpecialCategory.housing.id), isFalse);
      expect(SpecialCategory.isFlowId(SpecialCategory.income.id), isTrue);
      expect(SpecialCategory.isFlowId(SpecialCategory.transfer.id), isTrue);
      expect(SpecialCategory.isFlowId(SpecialCategory.investments.id), isTrue);
      expect(SpecialCategory.isSpecialId(SpecialCategory.housing.id), isTrue);
      expect(SpecialCategory.isHousingId(SpecialCategory.housing.id), isTrue);
    });

    test('builtInCaption uses Built-in language only for specials', () {
      expect(
        SpecialCategory.housing.asSpendCategory().builtInCaption,
        'Built-in · housing',
      );
      expect(
        SpecialCategory.income.asSpendCategory().builtInCaption,
        'Built-in · income',
      );
      expect(
        SpecialCategory.transfer.asSpendCategory().builtInCaption,
        'Built-in · transfer',
      );
      expect(
        const SpendCategory(
          id: 'cat_dining',
          name: 'Dining',
          sortOrder: 0,
          archived: false,
        ).builtInCaption,
        isNull,
      );
    });

    test('income ids are paychecks only, not investments or transfer', () {
      expect(SpecialCategory.isIncomeId(SpecialCategory.income.id), isTrue);
      expect(
        SpecialCategory.isIncomeId(SpecialCategory.investments.id),
        isFalse,
      );
      expect(SpecialCategory.isIncomeId(SpecialCategory.transfer.id), isFalse);
      expect(SpecialCategory.isInvestmentsName('Investments'), isTrue);
      expect(SpecialCategory.investments.asSpendCategory().isIncome, isFalse);
      expect(
        SpecialCategory.investments.asSpendCategory().isInvestments,
        isTrue,
      );
      expect(SpecialCategory.transfer.asSpendCategory().isIncome, isFalse);
    });
  });
}
