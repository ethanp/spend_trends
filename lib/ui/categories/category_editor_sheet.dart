import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/categories/category_spend_pace.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';
import 'package:spend_trends/data/repositories/categories_repository.dart';
import 'package:spend_trends/ui/widgets/app_primary_button.dart';
import 'package:spend_trends/ui/widgets/app_sheet_panel.dart';

import 'categories_providers.dart';
import 'category_editor_identity.dart';
import 'category_editor_merge.dart';
import 'category_spend_windows_row.dart';
import 'rule_match_caption_line.dart';

/// Create or edit a category name (and optional group membership).
class const CategoryEditorSheet({final SpendCategory? category})
    extends ConsumerStatefulWidget {
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    SpendCategory? category,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CategoryEditorSheet(category: category),
    );
  }

  @override
  ConsumerState<CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState() extends ConsumerState<CategoryEditorSheet> {
  late final TextEditingController _nameController;
  ConsciousSpendingArea? _selectedArea;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.category != null;

  bool get _isImmutableBuiltin => widget.category?.lockedCaption != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _selectedArea = widget.category?.consciousSpendingArea;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isImmutableBuiltin) {
      return AppSheetPanel.compact(
        child: Padding(
          padding: const EdgeInsets.all(ELayout.spaceLg),
          child: _immutableBuiltinBody(),
        ),
      );
    }
    if (!_isEditing) {
      return AppSheetPanel.compact(
        child: Padding(
          padding: const EdgeInsets.all(ELayout.spaceLg),
          child: _createBody(),
        ),
      );
    }
    return AppSheetPanel(
      heightFraction: 0.72,
      child: Padding(
        padding: const EdgeInsets.all(ELayout.spaceLg),
        child: _editBody(),
      ),
    );
  }

  Widget _immutableBuiltinBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Built-in category', style: EText.section),
        const SizedBox(height: ELayout.spaceMd),
        Text(
          widget.category!.name,
          style: EText.section.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        Text(widget.category!.lockedCaption!, style: EText.caption),
        const SizedBox(height: ELayout.spaceMd),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _identityFields({required bool autofocus}) {
    return CategoryEditorIdentityFields(
      nameController: _nameController,
      autofocus: autofocus,
      selectedArea: _selectedArea,
      onAreaSelected: (area) => setState(() => _selectedArea = area),
    );
  }

  Widget _createBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('New category', style: EText.section),
        const SizedBox(height: ELayout.spaceMd),
        _identityFields(autofocus: true),
        if (_error != null) ...[
          const SizedBox(height: ELayout.spaceSm),
          _errorMessage(),
        ],
        const SizedBox(height: ELayout.spaceMd),
        AppPrimaryButton(
          busy: _busy,
          onPressed: _save,
          child: const Text('Create'),
        ),
      ],
    );
  }

  Widget _editBody() {
    final category = widget.category!;
    CategorySpendPace? spendPace;
    for (final categoryPace
        in ref.watch(categorySpendPacesProvider).asData?.value ??
            const <CategorySpendPace>[]) {
      if (categoryPace.categoryId == category.id) spendPace = categoryPace;
    }
    final rules =
        ref.watch(categorizationRulesProvider).asData?.value ??
        const <CategorizationRule>[];
    final categoryRules = [
      for (final rule in rules)
        if (rule.categoryId == category.id) rule,
    ];

    return ListView(
      children: [
        Text(category.name, style: EText.section),
        if (category.isHousing) ...[
          const SizedBox(height: ELayout.spaceXs),
          Text('Built-in · housing', style: EText.caption),
        ],
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Identity',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        _identityFields(autofocus: false),
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Average spend per month',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        CategorySpendWindowsRow(
          monthlyCents: (window) => spendPace?.monthlyCents(window) ?? 0,
        ),
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Rules',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        _rulesPeek(categoryRules),
        if (_error != null) ...[
          const SizedBox(height: ELayout.spaceMd),
          _errorMessage(),
        ],
        const SizedBox(height: ELayout.spaceLg),
        AppPrimaryButton(
          busy: _busy,
          onPressed: _save,
          child: const Text('Save'),
        ),
        if (!category.isHousing) ...[
          const SizedBox(height: ELayout.spaceMd),
          CategoryEditorRetireSection(
            onMergeStarted: _busy ? null : _startMergeAndDelete,
          ),
        ],
      ],
    );
  }

  Widget _rulesPeek(List<CategorizationRule> categoryRules) {
    if (categoryRules.isEmpty) {
      return Text(
        'No merchant rules yet. Add them from Activity when categorizing.',
        style: EText.caption,
      );
    }
    final preview = categoryRules.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          categoryRules.length == 1
              ? '1 rule'
              : '${categoryRules.length} rules',
          style: EText.body.medium,
        ),
        const SizedBox(height: ELayout.spaceXs),
        for (final rule in preview)
          Padding(
            padding: const EdgeInsets.only(bottom: ELayout.spaceXs),
            child: RuleMatchCaptionLine(rule: rule),
          ),
        if (categoryRules.length > preview.length)
          Text(
            '+${categoryRules.length - preview.length} more',
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
      ],
    );
  }

  Widget _errorMessage() {
    return Text(_error!, style: EText.caption.copyWith(color: EColors.danger));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repository = await ref.read(categoriesRepositoryProvider.future);
      await _persistCategory(repository, name);
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persistCategory(
    CategoriesRepository repository,
    String name,
  ) async {
    if (_isEditing) {
      final categoryId = widget.category!.id;
      await repository.renameCategory(categoryId: categoryId, name: name);
      await repository.setConsciousSpendingArea(
        categoryId: categoryId,
        area: _selectedArea,
      );
      return;
    }
    final created = await repository.createCategory(name: name);
    if (_selectedArea != null) {
      await repository.setConsciousSpendingArea(
        categoryId: created.id,
        area: _selectedArea,
      );
    }
  }

  Future<void> _startMergeAndDelete() async {
    final category = widget.category;
    if (category == null) return;

    final categories = await ref.read(categoriesListProvider.future);
    final mergeTargets = categories
        .where((candidate) => candidate.id != category.id)
        .toList();
    if (mergeTargets.isEmpty) {
      setState(
        () => _error =
            'Add another category first — retire works by merging into it.',
      );
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (pickerContext) => CategoryMergeTargetPicker(
        category: category,
        mergeTargets: mergeTargets,
        onTargetSelected: (target) {
          Navigator.of(pickerContext).pop();
          _confirmMerge(target);
        },
      ),
    );
  }

  Future<void> _confirmMerge(SpendCategory target) async {
    final category = widget.category;
    if (category == null) return;

    final shouldMerge = await CategoryMergeConfirmation.show(
      context: context,
      category: category,
      target: target,
    );
    if (shouldMerge != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = await ref.read(categoriesRepositoryProvider.future);
      await repository.mergeCategoryInto(
        fromCategoryId: category.id,
        intoCategoryId: target.id,
      );
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
