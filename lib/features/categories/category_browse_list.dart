import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_spend_pace.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/features/categories/category_list_sections.dart';
import 'package:spend_trends/features/categories/category_spend_windows_row.dart';
import 'package:spend_trends/util/category_color.dart';
import 'package:spend_trends/widgets/app_compact_fact_row.dart';

/// Shared title column width so every category card is the widest card.
class const CategoryBrowseColumnWidths({required final double title}) {
  static const titleMax = 260.0;
  static const leadingWidth = 10.0;
  static const trailingWidth = 16.0;

  factory measure({required List<CategoryListSection> sections}) {
    final titleStyle = EText.section.copyWith(fontWeight: FontWeight.w600);
    final titles = <String>[];
    final captions = <String>[];
    for (final section in sections) {
      titles.add(section.title);
      for (final category in section.categories) {
        titles.add(category.name);
        captions.add(CategoryBrowseFactRow.captionFor(category));
      }
    }
    return CategoryBrowseColumnWidths(
      title: math.min(
        titleMax,
        math.max(
          CategorySpendWindowsRow.width,
          math.max(
            titles.widestLaidOutWidth(titleStyle),
            captions.widestLaidOutWidth(EText.caption),
          ),
        ),
      ),
    );
  }
}

/// Left Categories browse list: grouped compact fact rows, each with its
/// average monthly spend over 2y · 1y · 6mo · 3mo.
class const CategoryBrowseList({
  required final List<CategoryListSection> sections,
  required final Map<String, CategorySpendPace> pacesByCategoryId,
  required final String? selectedCategoryId,
  required final void Function(CategoryListSection section) onGroupOpened,
  required final void Function(SpendCategory category) onCategorySelected,
  required final void Function(SpendCategory category) onCategoryOpened,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final columnWidths = CategoryBrowseColumnWidths.measure(sections: sections);
    return ListView(
      padding: ETabBarOverlay.paddingOf(context),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceMd),
          child: Text('Average spend per month', style: EText.caption),
        ),
        const SizedBox(height: ELayout.spaceMd),
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: ELayout.spaceLg),
          CategoryBrowseSection(
            section: sections[index],
            pacesByCategoryId: pacesByCategoryId,
            columnWidths: columnWidths,
            selectedCategoryId: selectedCategoryId,
            onGroupOpened: sections[index].group == null
                ? null
                : () => onGroupOpened(sections[index]),
            onCategorySelected: onCategorySelected,
            onCategoryOpened: onCategoryOpened,
          ),
        ],
      ],
    );
  }
}

class const CategoryBrowseSection({
  required final CategoryListSection section,
  required final Map<String, CategorySpendPace> pacesByCategoryId,
  required final CategoryBrowseColumnWidths columnWidths,
  required final String? selectedCategoryId,
  required final VoidCallback? onGroupOpened,
  required final void Function(SpendCategory category) onCategorySelected,
  required final void Function(SpendCategory category) onCategoryOpened,
}) extends StatelessWidget {
  bool get _hidesSpendTotal =>
      section.categories.isNotEmpty &&
      section.categories.every((category) => category.isFlow);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(),
        if (section.categories.isEmpty) ...[
          const SizedBox(height: ELayout.spaceSm),
          Text(
            'No categories · tap to edit',
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
        ],
        for (final category in section.categories) ...[
          const SizedBox(height: ELayout.spaceSm),
          CategoryBrowseFactRow(
            category: category,
            spendPace: pacesByCategoryId[category.id],
            columnWidths: columnWidths,
            selected: selectedCategoryId == category.id,
            onCategorySelected: () => onCategorySelected(category),
            onCategoryOpened: () => onCategoryOpened(category),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader() {
    return AppCompactFactRow(
      leading: const SizedBox(width: CategoryBrowseColumnWidths.leadingWidth),
      title: section.title,
      titleWidth: columnWidths.title,
      detail: _hidesSpendTotal
          ? null
          : CategorySpendWindowsRow(
              monthlyCents: section.monthlyCents,
              emphasized: false,
            ),
      trailing: onGroupOpened == null
          ? const SizedBox(width: CategoryBrowseColumnWidths.trailingWidth)
          : const Icon(
              Icons.chevron_right,
              size: CategoryBrowseColumnWidths.trailingWidth,
              color: EColors.textMuted,
            ),
      decorate: false,
      padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceMd),
      onActivated: onGroupOpened,
    );
  }
}

class const CategoryBrowseFactRow({
  required final SpendCategory category,
  required final CategorySpendPace? spendPace,
  required final CategoryBrowseColumnWidths columnWidths,
  required final bool selected,
  required final VoidCallback onCategorySelected,
  required final VoidCallback onCategoryOpened,
}) extends StatelessWidget {
  static String captionFor(SpendCategory category) =>
      category.builtInCaption ??
      category.consciousSpendingArea?.displayName ??
      'No spending area';

  @override
  Widget build(BuildContext context) {
    final tint = CategoryColor.forCategory(category);
    return AppCompactFactRow(
      leading: Container(
        width: CategoryBrowseColumnWidths.leadingWidth,
        height: CategoryBrowseColumnWidths.leadingWidth,
        decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      ),
      title: category.name,
      caption: captionFor(category),
      titleWidth: columnWidths.title,
      detail: category.isFlow
          ? null
          : CategorySpendWindowsRow(
              monthlyCents: (window) => spendPace?.monthlyCents(window) ?? 0,
            ),
      trailing: GestureDetector(
        onTap: onCategoryOpened,
        child: const Icon(
          Icons.chevron_right,
          size: CategoryBrowseColumnWidths.trailingWidth,
          color: EColors.textMuted,
        ),
      ),
      tintColor: tint,
      selected: selected,
      onActivated: onCategorySelected,
    );
  }
}
