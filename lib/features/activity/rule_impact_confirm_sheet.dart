import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/contains_pattern_rematch.dart';
import 'package:spend_trends/features/activity/existing_rule_overlaps.dart';
import 'package:spend_trends/features/activity/overlapping_merchant_contains_rules.dart';
import 'package:spend_trends/features/activity/rule_impact_match_row.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';
import 'package:spend_trends/widgets/category_picker.dart';
import 'package:spend_trends/widgets/select_all_none_row.dart';

export 'package:spend_trends/features/activity/overlapping_merchant_contains_rules.dart';

/// One proposed contains-rule and the existing transactions it would match.
class const RuleImpactGroup({
  required final String pattern,
  required final String categoryId,
  required final String categoryName,
  required final List<BankTransaction> transactions,
}) {
  RuleImpactGroup copyWith({
    String? pattern,
    String? categoryId,
    String? categoryName,
    List<BankTransaction>? transactions,
  }) {
    return RuleImpactGroup(
      pattern: pattern ?? this.pattern,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      transactions: transactions ?? this.transactions,
    );
  }
}

/// Confirmed selection plus final (possibly edited) rule groups.
class const RuleImpactConfirmResult({
  required final Set<String> selectedTransactionIds,
  required final List<RuleImpactGroup> groups,
});

/// Confirms which matching transactions should receive the new rule’s category.
///
/// Lets you edit the contains pattern; rematches live and reveals existing
/// rules that are a substring or superstring of the candidate.
class const RuleImpactConfirmSheet({
  required final List<RuleImpactGroup> groups,
}) extends ConsumerStatefulWidget {
  static Future<RuleImpactConfirmResult?> show(
    BuildContext context, {
    required List<RuleImpactGroup> groups,
  }) {
    if (groups.isEmpty) {
      return Future.value(
        const RuleImpactConfirmResult(selectedTransactionIds: {}, groups: []),
      );
    }

    return showModalBottomSheet<RuleImpactConfirmResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RuleImpactConfirmSheet(groups: groups),
    );
  }

  @override
  ConsumerState<RuleImpactConfirmSheet> createState() =>
      _RuleImpactConfirmSheetState();
}

class _RuleImpactConfirmSheetState()
    extends ConsumerState<RuleImpactConfirmSheet> {
  late final List<TextEditingController> _patternControllers;
  late final List<FocusNode> _patternFocusNodes;
  late final List<ContainsPatternRematch> _rematches;
  late List<RuleImpactGroup> _groups;
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _groups = List<RuleImpactGroup>.from(widget.groups);
    _patternControllers = [
      for (final group in _groups) TextEditingController(text: group.pattern),
    ];
    _patternFocusNodes = [for (final _ in _groups) FocusNode()];
    _selectedIds = {
      for (final group in _groups)
        for (final transaction in group.transactions) transaction.id,
    };
    _rematches = [
      for (var groupIndex = 0; groupIndex < _groups.length; groupIndex++)
        ContainsPatternRematch(
          fetchMatches: (pattern) async {
            final categorizer = await ref.read(categorizerProvider.future);
            return categorizer.transactionsMatchingContains(pattern);
          },
          notify: () => _replaceGroupWithRematch(groupIndex),
        ),
    ];
    for (var groupIndex = 0; groupIndex < _groups.length; groupIndex++) {
      _rematches[groupIndex].matches = _groups[groupIndex].transactions;
    }
  }

  void _replaceGroupWithRematch(int groupIndex) {
    if (!mounted) return;
    setState(() {
      final rematch = _rematches[groupIndex];
      final previousIds = {
        for (final transaction in _groups[groupIndex].transactions)
          transaction.id,
      };
      _groups[groupIndex] = _groups[groupIndex].copyWith(
        pattern: _patternControllers[groupIndex].text.trim(),
        transactions: rematch.matches,
      );
      if (rematch.rematching) return;
      _selectedIds.removeAll(previousIds);
      _selectedIds.addAll([
        for (final transaction in rematch.matches) transaction.id,
      ]);
    });
  }

  @override
  void dispose() {
    for (final rematch in _rematches) {
      rematch.dispose();
    }
    for (final controller in _patternControllers) {
      controller.dispose();
    }
    for (final focusNode in _patternFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  int get _matchCount =>
      _groups.fold<int>(0, (sum, group) => sum + group.transactions.length);

  @override
  Widget build(BuildContext context) {
    final existingRules =
        ref.watch(categorizationRulesProvider).asData?.value ??
        const <CategorizationRule>[];
    final categories =
        ref.watch(categoriesListProvider).asData?.value ??
        const <SpendCategory>[];
    final categoryGroups =
        ref.watch(categoryGroupsProvider).asData?.value ??
        const <CategoryGroup>[];
    final categoryNameById = {
      for (final category in categories) category.id: category.name,
    };

    return AppSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(
            child: _matchList(
              existingRules: existingRules,
              categoryNameById: categoryNameById,
              categories: categories,
              categoryGroups: categoryGroups,
            ),
          ),
          _actions(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        ELayout.spaceLg,
        ELayout.spaceLg,
        ELayout.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Apply rule to existing?', style: EText.section),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            _matchCount == 0
                ? 'Edit the contains pattern below. Matching transactions '
                      'appear as you type. The rule still applies to future matches.'
                : 'These $_matchCount existing transactions match. '
                      'Edit the pattern to refine, turn off any that should stay, '
                      'and the rule will still apply to future matches.',
            style: EText.caption,
          ),
          const SizedBox(height: ELayout.spaceMd),
          _selectionShortcuts(),
        ],
      ),
    );
  }

  Widget _selectionShortcuts() {
    return SelectAllNoneRow(
      onAllSelected: _selectAll,
      onNoneSelected: _selectNone,
    );
  }

  Widget _matchList({
    required List<CategorizationRule> existingRules,
    required Map<String, String> categoryNameById,
    required List<SpendCategory> categories,
    required List<CategoryGroup> categoryGroups,
  }) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceLg),
      children: [
        for (var groupIndex = 0; groupIndex < _groups.length; groupIndex++)
          ..._groupSection(
            groupIndex: groupIndex,
            existingRules: existingRules,
            categoryNameById: categoryNameById,
            categories: categories,
            categoryGroups: categoryGroups,
          ),
      ],
    );
  }

  List<Widget> _groupSection({
    required int groupIndex,
    required List<CategorizationRule> existingRules,
    required Map<String, String> categoryNameById,
    required List<SpendCategory> categories,
    required List<CategoryGroup> categoryGroups,
  }) {
    final group = _groups[groupIndex];
    final rematch = _rematches[groupIndex];
    final related = overlappingMerchantContainsRules(
      candidatePattern: _patternControllers[groupIndex].text,
      existingRules: existingRules,
      categoryNameById: categoryNameById,
    );

    return [
      _TargetCategoryButton(
        categoryName: group.categoryName,
        onActivated: () => _pickTargetCategory(
          groupIndex: groupIndex,
          categories: categories,
          categoryGroups: categoryGroups,
        ),
      ),
      const SizedBox(height: ELayout.spaceXs),
      TextField(
        controller: _patternControllers[groupIndex],
        focusNode: _patternFocusNodes[groupIndex],
        decoration: EInput.filledMd(hintText: 'contains pattern'),
        style: EText.body.medium.copyWith(color: EColors.textPrimary),
        onChanged: (value) {
          setState(() {});
          rematch.schedule(value);
        },
      ),
      ExistingRuleOverlaps(overlaps: related),
      if (rematch.rematching) ...[
        const SizedBox(height: ELayout.spaceSm),
        const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
      const SizedBox(height: ELayout.spaceSm),
      if (group.transactions.isEmpty && !rematch.rematching)
        Padding(
          padding: const EdgeInsets.only(bottom: ELayout.spaceMd),
          child: Text(
            'No existing transactions match this pattern.',
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
        ),
      for (final transaction in group.transactions)
        RuleImpactMatchRow(
          transaction: transaction,
          currentCategoryName: RuleImpactMatchRow.categoryLabel(
            transaction,
            categoryNameById,
          ),
          selected: _selectedIds.contains(transaction.id),
          onSelectionChanged: (selected) =>
              _setSelected(transaction.id, selected),
        ),
      const SizedBox(height: ELayout.spaceLg),
    ];
  }

  Future<void> _pickTargetCategory({
    required int groupIndex,
    required List<SpendCategory> categories,
    required List<CategoryGroup> categoryGroups,
  }) async {
    final selected = await showModalBottomSheet<SpendCategory>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TargetCategoryPickerSheet(
        categories: categories,
        groups: categoryGroups,
        selectedCategoryId: _groups[groupIndex].categoryId,
        onCategorySelected: (category) =>
            Navigator.of(sheetContext).pop(category),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _groups[groupIndex] = _groups[groupIndex].copyWith(
        categoryId: selected.id,
        categoryName: selected.name,
      );
    });
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.all(ELayout.spaceLg),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          Expanded(
            child: AppPrimaryButton(
              onPressed: _confirm,
              child: Text(
                _selectedIds.isEmpty
                    ? 'Create rule only'
                    : 'Apply to ${_selectedIds.length}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    final finalizedGroups = [
      for (var groupIndex = 0; groupIndex < _groups.length; groupIndex++)
        _groups[groupIndex].copyWith(
          pattern: _patternControllers[groupIndex].text.trim(),
        ),
    ];
    for (final group in finalizedGroups) {
      if (group.pattern.isEmpty) return;
    }
    Navigator.of(context).pop(
      RuleImpactConfirmResult(
        selectedTransactionIds: Set<String>.from(_selectedIds),
        groups: finalizedGroups,
      ),
    );
  }

  void _setSelected(String transactionId, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(transactionId);
      } else {
        _selectedIds.remove(transactionId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll([
          for (final group in _groups)
            for (final transaction in group.transactions) transaction.id,
        ]);
    });
  }

  void _selectNone() {
    setState(_selectedIds.clear);
  }
}

class const _TargetCategoryButton({
  required final String categoryName,
  required final VoidCallback onActivated,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onActivated,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Text(
            '→ ',
            style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
          ),
          Flexible(
            child: Text(
              categoryName,
              style: EText.body.medium.copyWith(
                fontWeight: FontWeight.w600,
                color: FinanceColors.accentPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: FinanceColors.accentPrimary,
          ),
        ],
      ),
    );
  }
}

class const _TargetCategoryPickerSheet({
  required final List<SpendCategory> categories,
  required final List<CategoryGroup> groups,
  required final String selectedCategoryId,
  required final ValueChanged<SpendCategory> onCategorySelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppSheetPanel(
      heightFraction: 0.55,
      padForKeyboard: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(ELayout.spaceLg),
            child: Text('Target category', style: EText.section),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                ELayout.spaceLg,
                0,
                ELayout.spaceLg,
                ELayout.spaceLg,
              ),
              children: [
                CategoryPicker(
                  categories: categories,
                  groups: groups,
                  selectedId: selectedCategoryId,
                  onCategorySelected: onCategorySelected,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
