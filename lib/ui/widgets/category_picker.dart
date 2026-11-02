import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/category_group.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';
import 'package:spend_trends/ui/theme/category_color.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// One titled block of category chips (named group or ungrouped).
class const CategoryPickerSection({
  required final String? title,
  required final List<SpendCategory> categories,
});

/// Groups active categories into picker sections (named groups → ungrouped).
class CategoryPickerSections._(final List<CategoryPickerSection> sections) {
  factory from({
    required List<SpendCategory> categories,
    required List<CategoryGroup> groups,
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

    final sections = <CategoryPickerSection>[];
    for (final group in groups) {
      final members = membersByGroupId[group.id];
      if (members == null || members.isEmpty) continue;
      members.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
      sections.add(
        CategoryPickerSection(title: group.name, categories: members),
      );
    }
    ungrouped.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    if (ungrouped.isNotEmpty) {
      sections.add(
        CategoryPickerSection(
          title: sections.isEmpty ? null : 'Ungrouped',
          categories: ungrouped,
        ),
      );
    }
    return CategoryPickerSections._(sections);
  }
}

/// Renders [CategoryPickerSections] as titled chip wraps.
class const CategoryPicker({
  required final List<SpendCategory> categories,
  required final List<CategoryGroup> groups,
  required final String? selectedId,
  required final ValueChanged<SpendCategory> onCategorySelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sections = CategoryPickerSections.from(
      categories: categories,
      groups: groups,
    ).sections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: ELayout.spaceMd),
          _CategoryPickerSectionBlock(
            section: sections[index],
            selectedId: selectedId,
            onCategorySelected: onCategorySelected,
          ),
        ],
      ],
    );
  }
}

class const _CategoryPickerSectionBlock({
  required final CategoryPickerSection section,
  required final String? selectedId,
  required final ValueChanged<SpendCategory> onCategorySelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title != null) ...[
          Text(
            section.title!,
            style: EText.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: FinanceColors.accentPrimary,
            ),
          ),
          const SizedBox(height: ELayout.spaceXs),
        ],
        Wrap(
          spacing: ELayout.spaceSm,
          runSpacing: ELayout.spaceSm,
          children: [
            for (final category in section.categories)
              EFilterChip(
                label: category.name,
                color: CategoryColor.forCategory(category),
                selected: category.id == selectedId,
                onActivated: () => onCategorySelected(category),
              ),
          ],
        ),
      ],
    );
  }
}
