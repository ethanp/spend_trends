import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/month_summary.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/features/categories/category_list_sections.dart';
import 'package:spend_trends/util/category_color.dart';
import 'package:spend_trends/widgets/app_compact_fact_row.dart';

/// Shared title and amount columns so every category card is the widest card.
class const CategoryBrowseColumnWidths({
  required final double title,
  required final double amount,
}) {
  static const amountHeader = 'This month';
  static const titleMax = 260.0;
  static const leadingWidth = 10.0;
  static const trailingWidth = 16.0;

  factory measure({
    required List<CategoryListSection> sections,
    required Map<String, CategoryMonthRow> rowsById,
  }) {
    final titleStyle = EText.section.copyWith(fontWeight: FontWeight.w600);
    final captionStyle = EText.caption;
    final amountStyle = EText.body.medium.copyWith(fontWeight: FontWeight.w600);
    final titles = <String>[];
    final captions = <String>[];
    final amounts = <String>[formatCents(0)];

    for (final section in sections) {
      titles.add(section.title);
      if (section.categories.any((category) => !category.isFlow)) {
        amounts.add(formatCents(section.monthTotalCents));
      }
      for (final category in section.categories) {
        titles.add(category.name);
        captions.add(
          CategoryBrowseFactRow.captionFor(category, rowsById[category.id]),
        );
        if (!category.isFlow) {
          amounts.add(formatCents(rowsById[category.id]?.spentCents ?? 0));
        }
      }
    }

    return CategoryBrowseColumnWidths(
      title: math.min(
        titleMax,
        math.max(
          titles.widestLaidOutWidth(titleStyle),
          captions.widestLaidOutWidth(captionStyle),
        ),
      ),
      amount: math.max(
        amountHeader.laidOutWidth(EText.caption),
        amounts.widestLaidOutWidth(amountStyle),
      ),
    );
  }
}

/// Left Categories browse list (month strip + grouped compact fact rows).
class const CategoryBrowseList({
  required final String yearMonthLabel,
  required final List<CategoryListSection> sections,
  required final Map<String, CategoryMonthRow> rowsById,
  required final String? selectedCategoryId,
  required final void Function(CategoryListSection section) onGroupOpened,
  required final void Function(SpendCategory category) onCategorySelected,
  required final void Function(SpendCategory category) onCategoryOpened,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final columnWidths = CategoryBrowseColumnWidths.measure(
      sections: sections,
      rowsById: rowsById,
    );
    return ListView(
      padding: const EdgeInsets.all(ELayout.spaceLg)
          .withOverlaidTabBar(context),
      children: [
        _columnHeader(columnWidths),
        const SizedBox(height: ELayout.spaceMd),
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: ELayout.spaceLg),
          CategoryBrowseSection(
            section: sections[index],
            rowsById: rowsById,
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

  Widget _columnHeader(CategoryBrowseColumnWidths columnWidths) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceMd),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: CategoryBrowseColumnWidths.leadingWidth),
          const SizedBox(width: ELayout.spaceMd),
          SizedBox(
            width: columnWidths.title,
            child: Text(yearMonthLabel, style: EText.caption),
          ),
          const SizedBox(width: ELayout.spaceMd),
          SizedBox(
            width: columnWidths.amount,
            child: Text(
              CategoryBrowseColumnWidths.amountHeader,
              style: EText.caption,
              maxLines: 1,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: ELayout.spaceSm),
          const SizedBox(width: CategoryBrowseColumnWidths.trailingWidth),
        ],
      ),
    );
  }
}

class const CategoryBrowseSection({
  required final CategoryListSection section,
  required final Map<String, CategoryMonthRow> rowsById,
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
            row: rowsById[category.id],
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
      amount: _hidesSpendTotal
          ? const SizedBox.shrink()
          : Text(
              formatCents(section.monthTotalCents),
              style: EText.caption.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
            ),
      amountWidth: columnWidths.amount,
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
  required final CategoryMonthRow? row,
  required final CategoryBrowseColumnWidths columnWidths,
  required final bool selected,
  required final VoidCallback onCategorySelected,
  required final VoidCallback onCategoryOpened,
}) extends StatelessWidget {
  static String captionFor(SpendCategory category, CategoryMonthRow? row) {
    final builtInCaption = category.builtInCaption;
    if (builtInCaption != null) return builtInCaption;
    final annual = row?.annualizedSpendCents ?? 0;
    if (annual == 0) return 'No annual pace yet';
    return '${formatCents(annual)} / yr';
  }

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
      caption: captionFor(category, row),
      titleWidth: columnWidths.title,
      amount: category.isFlow
          ? const SizedBox.shrink()
          : Text(
              formatCents(row?.spentCents ?? 0),
              style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
            ),
      amountWidth: columnWidths.amount,
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
