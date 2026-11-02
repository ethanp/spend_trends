import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/ui/categories/category_list_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('categories are sectioned by spending area, then Not spending', () {
    final sections = CategoryListSections.from(
      categories: [
        SpecialCategory.income.asSpendCategory(),
        SpecialCategory.transfer.asSpendCategory(),
        SpecialCategory.investments.asSpendCategory(),
        SpecialCategory.housing.asSpendCategory(),
        const SpendCategory(
          id: 'cat_dining',
          name: 'Dining',
          sortOrder: 1,
          archived: false,
          consciousSpendingArea: ConsciousSpendingArea.guiltFree,
        ),
        const SpendCategory(
          id: 'cat_new',
          name: 'New',
          sortOrder: 2,
          archived: false,
        ),
      ],
      pacesByCategoryId: const {},
    ).sections;

    expect(sections.map((section) => section.title), [
      'Fixed Costs',
      'Investments',
      'Guilt-free',
      'Not spending',
      'No spending area',
    ]);
    List<String> namesIn(String title) => sections
        .firstWhere((section) => section.title == title)
        .categories
        .map((category) => category.name)
        .toList();
    expect(namesIn('Fixed Costs'), ['Housing']);
    expect(namesIn('Investments'), ['Investments']);
    expect(namesIn('Guilt-free'), ['Dining']);
    expect(namesIn('Not spending'), ['Income', 'Transfer']);
    expect(namesIn('No spending area'), ['New']);
  });
}
