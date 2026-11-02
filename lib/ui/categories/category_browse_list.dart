import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/category_spend_pace.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/ui/categories/category_list_sections.dart';
import 'package:spend_trends/ui/categories/category_spend_windows_row.dart';
import 'package:spend_trends/ui/theme/category_color.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';

abstract final class _TileLayout() {
  static const dotSize = 10.0;
  static const chevronSize = 18.0;

  /// Spend strip and dividers start under the name, past the dot.
  static const contentInset = dotSize + ELayout.spaceMd;
}

/// Left Categories browse list: grouped list tiles, each with its average
/// monthly spend over 2y · 1y · 6mo · 3mo.
class const CategoryBrowseList({
  required final List<CategoryListSection> sections,
  required final Map<String, CategorySpendPace> pacesByCategoryId,
  required final String? selectedCategoryId,
  required final void Function(SpendCategory category) onCategorySelected,
  required final void Function(SpendCategory category) onCategoryOpened,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: ETabBarOverlay.paddingOf(context),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceMd),
          child: Text('Average spend per month', style: EText.caption),
        ),
        const SizedBox(height: ELayout.spaceSm),
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: ELayout.spaceLg),
          CategoryBrowseSection(
            section: sections[index],
            pacesByCategoryId: pacesByCategoryId,
            selectedCategoryId: selectedCategoryId,
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
  required final String? selectedCategoryId,
  required final void Function(SpendCategory category) onCategorySelected,
  required final void Function(SpendCategory category) onCategoryOpened,
}) extends StatelessWidget {
  bool get _hidesSpendTotal =>
      section.categories.isNotEmpty &&
      section.categories.every((category) => category.isFlow);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(),
        for (var index = 0; index < section.categories.length; index++) ...[
          if (index > 0) _tileDivider(),
          CategoryBrowseTile(
            category: section.categories[index],
            spendPace: pacesByCategoryId[section.categories[index].id],
            selected: selectedCategoryId == section.categories[index].id,
            onCategorySelected: () =>
                onCategorySelected(section.categories[index]),
            onCategoryOpened: () => onCategoryOpened(section.categories[index]),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader() {
    return Padding(
      padding: const EdgeInsets.all(ELayout.spaceSm)
          .copyWith(left: ELayout.spaceMd, right: ELayout.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            section.title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EText.caption.copyWith(
              color: EColors.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          if (!_hidesSpendTotal) ...[
            const SizedBox(height: ELayout.spaceXs),
            CategorySpendWindowsRow(
              monthlyCents: section.monthlyCents,
              emphasized: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _tileDivider() => const Divider(
    height: 1,
    thickness: 0.5,
    indent: ELayout.spaceMd + _TileLayout.contentInset,
    color: EColors.border,
  );
}

class const CategoryBrowseTile({
  required final SpendCategory category,
  required final CategorySpendPace? spendPace,
  required final bool selected,
  required final VoidCallback onCategorySelected,
  required final VoidCallback onCategoryOpened,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCategorySelected,
      child: ColoredBox(
        color: selected
            ? FinanceColors.accentPrimary.withValues(alpha: 0.14)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(ELayout.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _identityLine(),
              if (!category.isFlow) ...[
                const SizedBox(height: ELayout.spaceSm),
                Padding(
                  padding: const EdgeInsets.only(
                    left: _TileLayout.contentInset,
                  ),
                  child: CategorySpendWindowsRow(
                    monthlyCents: (window) =>
                        spendPace?.monthlyCents(window) ?? 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _identityLine() {
    return Row(
      children: [
        Container(
          width: _TileLayout.dotSize,
          height: _TileLayout.dotSize,
          decoration: BoxDecoration(
            color: CategoryColor.forCategory(category),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: ELayout.spaceMd),
        Expanded(
          child: Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EText.section.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCategoryOpened,
          child: const Padding(
            padding: EdgeInsets.all(ELayout.spaceXs),
            child: Icon(
              Icons.chevron_right,
              size: _TileLayout.chevronSize,
              color: EColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
