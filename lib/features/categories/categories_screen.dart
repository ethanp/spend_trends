import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/month_summary.dart';
import 'package:spend_trends/features/categories/categories_burn_pane.dart';
import 'package:spend_trends/features/categories/category_browse_list.dart';
import 'package:spend_trends/features/categories/category_editor_sheet.dart';
import 'package:spend_trends/features/categories/category_list_sections.dart';
import 'package:spend_trends/features/categories/group_editor_sheet.dart';
import 'package:spend_trends/providers/spend_trends_providers.dart';
import 'package:spend_trends/widgets/app_browse_split_shell.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';
import 'package:spend_trends/widgets/sync_status_nav_button.dart';

class const CategoriesScreen() extends ConsumerStatefulWidget {
  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState() extends ConsumerState<CategoriesScreen> {
  static const _rightPaneWidth = 640.0;
  static final _monthLabelFormat = DateFormat('MMM yyyy');

  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final String yearMonth = ref.watch(currentYearMonthProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final groupsAsync = ref.watch(categoryGroupsProvider);
    final rowsAsync = ref.watch(categoryMonthRowsProvider(yearMonth));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Categories',
        leading: const SyncStatusNavButton(),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddMenu(context),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: _body(
          yearMonth: yearMonth,
          categoriesAsync: categoriesAsync,
          groupsAsync: groupsAsync,
          rowsAsync: rowsAsync,
        ),
      ),
    );
  }

  Widget _body({
    required String yearMonth,
    required AsyncValue<List<SpendCategory>> categoriesAsync,
    required AsyncValue<List<CategoryGroup>> groupsAsync,
    required AsyncValue<List<CategoryMonthRow>> rowsAsync,
  }) {
    if (categoriesAsync.isLoading || groupsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (categoriesAsync.hasError) {
      return Center(
        child: Text(
          '${categoriesAsync.error}',
          style: EText.body.medium.copyWith(color: EColors.danger),
        ),
      );
    }
    if (groupsAsync.hasError) {
      return Center(
        child: Text(
          '${groupsAsync.error}',
          style: EText.body.medium.copyWith(color: EColors.danger),
        ),
      );
    }

    final categories = categoriesAsync.requireValue;
    if (categories.isEmpty) return _emptyState(context);

    final groups = groupsAsync.requireValue;
    final rowsById = {
      for (final row in rowsAsync.asData?.value ?? <CategoryMonthRow>[])
        row.categoryId: row,
    };
    final sections = CategoryListSections.from(
      categories: categories,
      groups: groups,
      rowsById: rowsById,
    ).sections;
    final categoriesById = {
      for (final category in categories) category.id: category,
    };

    return AppBrowseSplitShell(
      initialSizedWidth: _rightPaneWidth,
      maxSizedWidth: _rightPaneWidth,
      left: CategoryBrowseList(
        yearMonthLabel: _formatYearMonth(yearMonth),
        sections: sections,
        rowsById: rowsById,
        selectedCategoryId: _selectedCategoryId,
        onGroupOpened: (section) =>
            GroupEditorSheet.show(context, ref: ref, group: section.group),
        onCategorySelected: _selectCategory,
        onCategoryOpened: (category) =>
            CategoryEditorSheet.show(context, ref: ref, category: category),
      ),
      right: CategoriesBurnPane(
        selectedCategoryId: _selectedCategoryId,
        categoriesById: categoriesById,
        rowsById: rowsById,
        onCategoryOpened: (category) =>
            CategoryEditorSheet.show(context, ref: ref, category: category),
      ),
    );
  }

  void _selectCategory(SpendCategory category) {
    if (!AppBrowseSplitShell.isSplit(context)) {
      CategoryEditorSheet.show(context, ref: ref, category: category);
      return;
    }
    if (_selectedCategoryId == category.id) {
      CategoryEditorSheet.show(context, ref: ref, category: category);
      return;
    }
    setState(() => _selectedCategoryId = category.id);
  }

  String _formatYearMonth(String yearMonth) {
    final parts = yearMonth.split('-');
    if (parts.length != 2) return yearMonth;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return yearMonth;
    return _monthLabelFormat.format(DateTime(year, month));
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppSheetPanel.compact(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Add category'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                CategoryEditorSheet.show(context, ref: ref);
              },
            ),
            ListTile(
              title: const Text('Add group'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                GroupEditorSheet.show(context, ref: ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ELayout.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No categories yet', style: EText.section),
            const SizedBox(height: ELayout.spaceSm),
            Text(
              'Add categories to organize spending.',
              style: EText.body.medium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ELayout.spaceLg),
            AppPrimaryButton(
              onPressed: () => CategoryEditorSheet.show(context, ref: ref),
              child: const Text('Add category'),
            ),
          ],
        ),
      ),
    );
  }
}
