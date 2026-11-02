import 'package:spend_trends/domain/categories/category.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/ui/categories/category_list_sections.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';
import 'package:spend_trends/ui/theme/category_color.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Category chips under spending-area titles, as on the Categories list.
class const CategoryPicker({
  required final List<SpendCategory> categories,
  required final String? selectedId,
  required final ValueChanged<SpendCategory> onCategorySelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sections = CategoryListSections.from(
      categories: categories,
      pacesByCategoryId: const {},
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
  required final CategoryListSection section,
  required final String? selectedId,
  required final ValueChanged<SpendCategory> onCategorySelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: EText.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: FinanceColors.accentPrimary,
          ),
        ),
        const SizedBox(height: ELayout.spaceXs),
        Wrap(
          spacing: ELayout.spaceSm,
          runSpacing: ELayout.spaceSm,
          children: section.categories.mapL(
            (category) => EFilterChip(
              label: category.name,
              color: CategoryColor.forCategory(category),
              selected: category.id == selectedId,
              onActivated: () => onCategorySelected(category),
            ),
          ),
        ),
      ],
    );
  }
}
