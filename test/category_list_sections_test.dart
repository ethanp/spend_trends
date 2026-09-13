import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/features/categories/category_list_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Transfer is ungrouped; Income and Investments sit in Income', () {
    final sections = CategoryListSections.from(
      categories: [
        SpecialCategory.income.asSpendCategory(),
        SpecialCategory.transfer.asSpendCategory(),
        SpecialCategory.investments.asSpendCategory(),
        const SpendCategory(
          id: 'cat_dining',
          name: 'Dining',
          sortOrder: 1,
          archived: false,
          groupId: 'grp_wants',
        ),
      ],
      groups: [
        const CategoryGroup(id: 'grp_wants', name: 'Wants', sortOrder: 0),
        SpecialCategory.incomeGroup,
      ],
      rowsById: const {},
    ).sections;

    expect(sections.map((section) => section.title), [
      'Wants',
      'Income',
      'Ungrouped',
    ]);
    expect(sections.any((section) => section.title == 'Cash flow'), isFalse);

    final incomeSection = sections.firstWhere(
      (section) => section.title == 'Income',
    );
    expect(
      incomeSection.categories.map((category) => category.name),
      containsAll(['Income', 'Investments']),
    );

    final ungrouped = sections.firstWhere(
      (section) => section.title == 'Ungrouped',
    );
    expect(ungrouped.categories.map((category) => category.name), ['Transfer']);
  });
}
