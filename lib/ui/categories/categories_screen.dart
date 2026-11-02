import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/data/repositories/categories_repository.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/ui/projections/fire_outlook_card.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/category_spend_pace.dart';
import 'package:spend_trends/ui/categories/categories_burn_pane.dart';
import 'package:spend_trends/ui/categories/category_browse_list.dart';
import 'package:spend_trends/ui/categories/category_editor_sheet.dart';
import 'package:spend_trends/ui/categories/category_list_sections.dart';
import 'package:spend_trends/ui/widgets/app_browse_split_shell.dart';
import 'package:spend_trends/ui/widgets/app_primary_button.dart';

import 'categories_providers.dart';

class const CategoriesScreen() extends ConsumerStatefulWidget {
  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState() extends ConsumerState<CategoriesScreen> {
  static const _rightPaneWidth = 640.0;

  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesListProvider);
    final pacesAsync = ref.watch(categorySpendPacesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Categories',
        leading: const ESyncPhaseIcon(),
        automaticallyImplyLeading: false,
        actions: [
          const FireOutlookCard(),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add category',
            onPressed: () => CategoryEditorSheet.show(context, ref: ref),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: _body(categoriesAsync: categoriesAsync, pacesAsync: pacesAsync),
      ),
    );
  }

  Widget _body({
    required AsyncValue<List<SpendCategory>> categoriesAsync,
    required AsyncValue<List<CategorySpendPace>> pacesAsync,
  }) {
    if (categoriesAsync.isLoading) {
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

    final categories = categoriesAsync.requireValue;
    if (categories.isEmpty) return _emptyState(context);

    final pacesByCategoryId = {
      for (final spendPace
          in pacesAsync.asData?.value ?? const <CategorySpendPace>[])
        spendPace.categoryId: spendPace,
    };
    final sections = CategoryListSections.from(
      categories: categories,
      pacesByCategoryId: pacesByCategoryId,
    ).sections;
    final categoriesById = {
      for (final category in categories) category.id: category,
    };

    return AppBrowseSplitShell(
      initialSizedWidth: _rightPaneWidth,
      maxSizedWidth: _rightPaneWidth,
      left: CategoryBrowseList(
        sections: sections,
        pacesByCategoryId: pacesByCategoryId,
        selectedCategoryId: _selectedCategoryId,
        onCategorySelected: _selectCategory,
        onCategoryOpened: (category) =>
            CategoryEditorSheet.show(context, ref: ref, category: category),
      ),
      right: CategoriesBurnPane(
        selectedCategoryId: _selectedCategoryId,
        categoriesById: categoriesById,
        pacesByCategoryId: pacesByCategoryId,
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
