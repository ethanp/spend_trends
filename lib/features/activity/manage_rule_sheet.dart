import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';
import 'package:spend_trends/widgets/category_picker.dart';

/// Lists transactions where [rule] is primary; retarget or remove the rule.
class const ManageRuleSheet({required final CategorizationRule rule})
    extends ConsumerStatefulWidget {
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    required CategorizationRule rule,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManageRuleSheet(rule: rule),
    );
  }

  @override
  ConsumerState<ManageRuleSheet> createState() => _ManageRuleSheetState();
}

class _ManageRuleSheetState() extends ConsumerState<ManageRuleSheet> {
  late CategorizationRule _rule = widget.rule;
  List<BankTransaction>? _primaryMatches;
  Object? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPrimaryMatches();
  }

  Future<void> _loadPrimaryMatches() async {
    try {
      final categorizer = await ref.read(categorizerProvider.future);
      final matches = await categorizer.transactionsExplainedByRule(_rule);
      if (!mounted) return;
      setState(() {
        _primaryMatches = matches;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesListProvider).asData?.value ??
        const <SpendCategory>[];
    final categoryNameById = {
      for (final category in categories) category.id: category.name,
    };
    final categoryName =
        categoryNameById[_rule.categoryId] ?? 'Unknown category';

    return AppSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(categoryName),
          Expanded(child: _body(categoryNameById)),
          _actions(),
        ],
      ),
    );
  }

  Widget _header(String categoryName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        ELayout.spaceLg,
        ELayout.spaceLg,
        ELayout.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rule', style: EText.section),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            'contains “${_rule.pattern}”',
            style: EText.body.medium.copyWith(
              fontWeight: FontWeight.w600,
              color: FinanceColors.accentPrimary,
            ),
          ),
          const SizedBox(height: ELayout.spaceXs),
          TextButton(
            onPressed: _busy ? null : _pickTargetCategory,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '→ $categoryName',
                  style: EText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: FinanceColors.accentPrimary,
                  ),
                ),
                const SizedBox(width: ELayout.spaceXs),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: FinanceColors.accentPrimary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Map<String, String> categoryNameById) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ELayout.spaceLg),
          child: Text(
            '$_loadError',
            style: EText.body.medium.copyWith(color: EColors.danger),
          ),
        ),
      );
    }
    final matches = _primaryMatches;
    if (matches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (matches.isEmpty) {
      return Center(
        child: Text(
          'No transactions currently use this rule.',
          style: EText.body.medium.copyWith(color: EColors.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        0,
        ELayout.spaceLg,
        ELayout.spaceMd,
      ),
      itemCount: matches.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: ELayout.spaceMd),
            child: Text(
              '${matches.length} '
              '${matches.length == 1 ? 'transaction' : 'transactions'} '
              'where this rule is primary',
              style: EText.caption.copyWith(color: EColors.textMuted),
            ),
          );
        }
        final transaction = matches[index - 1];
        return _PrimaryMatchRow(
          transaction: transaction,
          categoryName: _categoryLabel(transaction, categoryNameById),
        );
      },
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.all(ELayout.spaceLg),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
          Expanded(
            child: TextButton(
              onPressed: _busy ? null : _confirmRemove,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Remove rule',
                      style: EText.body.medium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: EColors.danger,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTargetCategory() async {
    final categories =
        ref.read(categoriesListProvider).asData?.value ??
        const <SpendCategory>[];
    final groups =
        ref.read(categoryGroupsProvider).asData?.value ??
        const <CategoryGroup>[];
    final selected = await showModalBottomSheet<SpendCategory>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TargetCategoryPickerSheet(
        categories: categories,
        groups: groups,
        selectedCategoryId: _rule.categoryId,
        onCategorySelected: (category) =>
            Navigator.of(sheetContext).pop(category),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected.id == _rule.categoryId) return;

    final matchCount = _primaryMatches?.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change rule category?'),
        content: Text(
          matchCount == 0
              ? 'Points this rule at ${selected.name}. No transactions '
                    'currently use it as primary.'
              : 'Points this rule at ${selected.name} and updates $matchCount '
                    '${matchCount == 1 ? 'transaction' : 'transactions'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final categorizer = await ref.read(categorizerProvider.future);
      await categorizer.retargetRule(rule: _rule, categoryId: selected.id);
      ref.read(spendDataChangedProvider.notifier).notify();
      if (!mounted) return;
      setState(() {
        _rule = CategorizationRule(
          id: _rule.id,
          matchType: _rule.matchType,
          pattern: _rule.pattern,
          categoryId: selected.id,
          priority: _rule.priority,
        );
        _busy = false;
        _primaryMatches = null;
      });
      await _loadPrimaryMatches();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Could not change category'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final matchCount = _primaryMatches?.length ?? 0;
        return AlertDialog(
          title: const Text('Remove this rule?'),
          content: Text(
            matchCount == 0
                ? 'The rule will be deleted. No transactions are currently '
                      'using it as primary.'
                : 'Deletes the rule and clears categories on $matchCount '
                      '${matchCount == 1 ? 'transaction' : 'transactions'}. '
                      'Remaining rules will reclaim matches as suggested.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Remove',
                style: TextStyle(color: EColors.danger),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final categorizer = await ref.read(categorizerProvider.future);
      await categorizer.removeRuleAndReclaim(_rule);
      ref.read(spendDataChangedProvider.notifier).notify();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Could not remove rule'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  static String _categoryLabel(
    BankTransaction transaction,
    Map<String, String> categoryNameById,
  ) {
    final categoryId = transaction.effectiveCategoryId;
    if (categoryId == null) return 'Uncategorized';
    return categoryNameById[categoryId] ?? 'Unknown category';
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

class const _PrimaryMatchRow({
  required final BankTransaction transaction,
  required final String categoryName,
}) extends StatelessWidget {
  String get _title => transaction.rawDescription.isEmpty
      ? transaction.normalizedMerchant
      : transaction.rawDescription;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.yMMMd().format(transaction.postedAt.toLocal());
    return Padding(
      padding: const EdgeInsets.only(bottom: ELayout.spaceSm),
      child: ESurface(
        kind: ESurfaceKind.row,
        padding: const EdgeInsets.symmetric(
          horizontal: ELayout.spaceMd,
          vertical: ELayout.spaceSm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: EText.body.medium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$categoryName · $dateLabel',
                    style: EText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: FinanceColors.accentPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: ELayout.spaceSm),
            Text(
              formatCents(transaction.amountCents),
              style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
