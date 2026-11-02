import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/category_spend_pace.dart';

/// One block on the Categories list: a named group or Ungrouped.
class const CategoryListSection({
  required final String title,
  required final List<SpendCategory> categories,
  required final Map<String, CategorySpendPace> pacesByCategoryId,

  /// Non-null when the header opens the group editor.
  final CategoryGroup? group,
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

/// Groups → Ungrouped; members sorted by 1y average spend desc.
class CategoryListSections._(final List<CategoryListSection> sections) {
  factory from({
    required List<SpendCategory> categories,
    required List<CategoryGroup> groups,
    required Map<String, CategorySpendPace> pacesByCategoryId,
  }) {
    final groupsById = {for (final group in groups) group.id: group};
    final membersByGroupId = <String, List<SpendCategory>>{};
    final ungrouped = <SpendCategory>[];

    for (final category in categories) {
      final groupId = category.groupId;
      if (groupId != null && groupsById.containsKey(groupId)) {
        membersByGroupId.putIfAbsent(groupId, () => []).add(category);
      } else {
        ungrouped.add(category);
      }
    }

    final sections = <CategoryListSection>[];
    for (final group in groups) {
      final members = List<SpendCategory>.from(
        membersByGroupId[group.id] ?? const <SpendCategory>[],
      );
      _sortByOneYearSpend(members, pacesByCategoryId);
      sections.add(
        CategoryListSection(
          title: group.name,
          group: group,
          categories: members,
          pacesByCategoryId: pacesByCategoryId,
        ),
      );
    }

    if (ungrouped.isNotEmpty) {
      _sortByOneYearSpend(ungrouped, pacesByCategoryId);
      sections.add(
        CategoryListSection(
          title: 'Ungrouped',
          categories: ungrouped,
          pacesByCategoryId: pacesByCategoryId,
        ),
      );
    }

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
