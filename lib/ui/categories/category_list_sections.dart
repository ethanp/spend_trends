import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/category_spend_pace.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/categories/special_category.dart';

/// One block on the Categories list: a spending area, Not spending, or
/// No spending area.
class const CategoryListSection({
  required final String title,
  required final List<SpendCategory> categories,
  required final Map<String, CategorySpendPace> pacesByCategoryId,
}) {
  /// The members' summed average monthly spend over [window].
  int monthlyCents(CategorySpendWindow window) {
    var totalCents = 0;
    for (final category in categories) {
      totalCents += pacesByCategoryId[category.id]?.monthlyCents(window) ?? 0;
    }
    return totalCents;
  }
}

/// Spending areas in plan order → Not spending (Income, Transfer, Asset
/// sale) → No spending area. Empty sections are left out; members sorted by
/// 1y average spend desc.
class CategoryListSections._(final List<CategoryListSection> sections) {
  static const notSpendingTitle = 'Not spending';
  static const noSpendingAreaTitle = 'No spending area';

  factory from({
    required List<SpendCategory> categories,
    required Map<String, CategorySpendPace> pacesByCategoryId,
  }) {
    final membersByArea = <ConsciousSpendingArea, List<SpendCategory>>{};
    final notSpending = <SpendCategory>[];
    final noSpendingArea = <SpendCategory>[];

    for (final category in categories) {
      final ConsciousSpendingArea? area = category.consciousSpendingArea;
      if (area != null) {
        membersByArea.putIfAbsent(area, () => []).add(category);
      } else if (category.isFlow) {
        notSpending.add(category);
      } else {
        noSpendingArea.add(category);
      }
    }

    final sections = <CategoryListSection>[];
    void addSection(String title, List<SpendCategory> members) {
      if (members.isEmpty) return;
      _sortByOneYearSpend(members, pacesByCategoryId);
      sections.add(
        CategoryListSection(
          title: title,
          categories: members,
          pacesByCategoryId: pacesByCategoryId,
        ),
      );
    }

    for (final area in ConsciousSpendingArea.values) {
      addSection(area.displayName, membersByArea[area] ?? []);
    }
    addSection(notSpendingTitle, notSpending);
    addSection(noSpendingAreaTitle, noSpendingArea);
    return CategoryListSections._(sections);
  }

  static void _sortByOneYearSpend(
    List<SpendCategory> categories,
    Map<String, CategorySpendPace> pacesByCategoryId,
  ) {
    int oneYearSpend(SpendCategory category) =>
        pacesByCategoryId[category.id]?.monthlyCents(
          CategorySpendWindow.oneYear,
        ) ??
        0;
    categories.sort((left, right) {
      final spendCompare = oneYearSpend(right).compareTo(oneYearSpend(left));
      if (spendCompare != 0) return spendCompare;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
  }
}
