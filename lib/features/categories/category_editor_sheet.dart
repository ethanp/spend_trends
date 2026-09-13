import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/month_summary.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

import 'categories_providers.dart';
import 'category_editor_identity.dart';
import 'category_editor_merge.dart';

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
  String? _selectedGroupId;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.category != null;

  /// Income / Transfer only — Housing and Investments stay editable.
  bool get _isImmutableBuiltin =>
      widget.category?.id == SpecialCategory.income.id ||
      widget.category?.id == SpecialCategory.transfer.id;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _selectedGroupId = widget.category?.groupId;
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
        Text(
          widget.category!.isIncome
              ? 'Income · excluded from spend trends. '
                    'It cannot be renamed or deleted.'
              : 'Transfer · excluded from spend trends. '
                    'It cannot be renamed or deleted. '
                    'Use it for money moving between your own accounts.',
          style: EText.caption,
        ),
        const SizedBox(height: ELayout.spaceMd),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _identityFields({required bool autofocus}) {
    final groups =
        ref.watch(categoryGroupsProvider).asData?.value ??
        const <CategoryGroup>[];
    return CategoryEditorIdentityFields(
      nameController: _nameController,
      autofocus: autofocus,
      groups: groups,
      selectedGroupId: _selectedGroupId,
      onGroupSelected: (groupId) => setState(() => _selectedGroupId = groupId),
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
    final yearMonth = ref.watch(currentYearMonthProvider);
    final monthRows =
        ref.watch(categoryMonthRowsProvider(yearMonth)).asData?.value ??
        const <CategoryMonthRow>[];
    CategoryMonthRow? monthRow;
    for (final row in monthRows) {
      if (row.categoryId == category.id) {
        monthRow = row;
        break;
      }
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
          'This month',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        _monthSpendLine(monthRow),
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

  Widget _monthSpendLine(CategoryMonthRow? monthRow) {
    final spent = monthRow?.spentCents ?? 0;
    final annual = monthRow?.annualizedSpendCents ?? 0;
    return Text(
      annual == 0
          ? '${formatCents(spent)} this month'
          : '${formatCents(spent)} this month · ${formatCents(annual)} / yr',
      style: EText.body.medium,
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
            child: Text(_ruleCaption(rule), style: EText.caption),
          ),
        if (categoryRules.length > preview.length)
          Text(
            '+${categoryRules.length - preview.length} more',
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
      ],
    );
  }

  String _ruleCaption(CategorizationRule rule) {
    final matchLabel = switch (rule.matchType) {
      RuleMatchType.merchantContains => 'contains',
      RuleMatchType.merchantExact => 'exact',
    };
    return '$matchLabel “${rule.pattern}”';
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
      await repository.setCategoryGroup(
        categoryId: categoryId,
        groupId: _selectedGroupId,
      );
      return;
    }
    final created = await repository.createCategory(name: name);
    if (_selectedGroupId != null) {
      await repository.setCategoryGroup(
        categoryId: created.id,
        groupId: _selectedGroupId,
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
