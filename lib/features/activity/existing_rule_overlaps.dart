import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/features/activity/overlapping_merchant_contains_rules.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/category_picker.dart';

/// Existing contains-rules that overlap a candidate pattern.
///
/// Each chip can retarget the rule’s category or delete the rule in place.
class const ExistingRuleOverlaps({
  required final List<RelatedExistingRule> overlaps,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: overlaps.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: ELayout.spaceSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Overlaps existing rules',
                    style: EText.caption.copyWith(
                      color: EColors.textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: ELayout.spaceXs),
                  Wrap(
                    spacing: ELayout.spaceSm,
                    runSpacing: ELayout.spaceSm,
                    children: [
                      for (final entry in overlaps)
                        _OverlappingRuleChip(
                          key: ValueKey(entry.rule.id),
                          entry: entry,
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class const _OverlappingRuleChip({
  super.key,
  required final RelatedExistingRule entry,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_OverlappingRuleChip> createState() =>
      _OverlappingRuleChipState();
}

class _OverlappingRuleChipState() extends ConsumerState<_OverlappingRuleChip> {
  bool _busy = false;

  Color get _accent => switch (widget.entry.relation) {
    RelatedRuleRelation.same => FinanceColors.accentPrimary,
    RelatedRuleRelation.broader => FinanceColors.accentSecondary,
    RelatedRuleRelation.narrower => FinanceColors.housing,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        left: ELayout.spaceMd,
        right: ELayout.spaceXs,
        top: ELayout.spaceXs,
        bottom: ELayout.spaceXs,
      ),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: ELayout.borderRadiusSm,
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.entry.relation.label} · ',
            style: EText.caption.copyWith(
              color: _accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              '“${widget.entry.rule.pattern}” → ',
              style: EText.caption.copyWith(color: EColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _OverlapRuleCategoryMenu(
            categoryName: widget.entry.categoryName,
            selectedCategoryId: widget.entry.rule.categoryId,
            enabled: !_busy,
            onCategorySelected: _retargetTo,
          ),
          _deleteRuleButton(),
        ],
      ),
    );
  }

  Widget _deleteRuleButton() {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: ELayout.spaceXs),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      tooltip: 'Delete rule',
      onPressed: _confirmDelete,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      style: IconButton.styleFrom(
        foregroundColor: EColors.textMuted,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.close, size: 16),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this rule?'),
        content: Text(
          'Removes “${widget.entry.rule.pattern}” → '
          '${widget.entry.categoryName}. Transactions it currently '
          'categorizes can be reclaimed by remaining rules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: EColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _deleteRule();
  }

  Future<void> _deleteRule() async {
    setState(() => _busy = true);
    try {
      final categorizer = await ref.read(categorizerProvider.future);
      await categorizer.removeRuleAndReclaim(widget.entry.rule);
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError(title: 'Could not delete rule', error: error);
    }
  }

  Future<void> _retargetTo(SpendCategory category) async {
    if (category.id == widget.entry.rule.categoryId) return;
    setState(() => _busy = true);
    try {
      final categorizer = await ref.read(categorizerProvider.future);
      await categorizer.retargetRule(
        rule: widget.entry.rule,
        categoryId: category.id,
      );
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError(title: 'Could not change category', error: error);
    }
  }

  Future<void> _showError({
    required String title,
    required Object error,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
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

class const _OverlapRuleCategoryMenu({
  required final String categoryName,
  required final String selectedCategoryId,
  required final ValueChanged<SpendCategory> onCategorySelected,
  required final bool enabled,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<SpendCategory> categories =
        ref.watch(categoriesListProvider).asData?.value ??
        const <SpendCategory>[];
    final List<CategoryGroup> groups =
        ref.watch(categoryGroupsProvider).asData?.value ??
        const <CategoryGroup>[];
    return MenuAnchor(
      consumeOutsideTap: true,
      alignmentOffset: const Offset(0, 4),
      style: _menuStyle(context),
      builder: (context, controller, child) => _categoryButton(controller),
      menuChildren: _categoryMenuItems(categories, groups),
    );
  }

  MenuStyle _menuStyle(BuildContext context) {
    return MenuStyle(
      backgroundColor: WidgetStateProperty.all(EColors.surfaceRaised),
      padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 4)),
      maximumSize: WidgetStateProperty.all(
        Size((MediaQuery.sizeOf(context).width - 48).clamp(200.0, 360.0), 420),
      ),
    );
  }

  Widget _categoryButton(MenuController controller) {
    return Tooltip(
      message: 'Change category',
      child: GestureDetector(
        onTap: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              categoryName,
              style: EText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: FinanceColors.accentPrimary,
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
      ),
    );
  }

  List<Widget> _categoryMenuItems(
    List<SpendCategory> categories,
    List<CategoryGroup> groups,
  ) {
    final List<CategoryPickerSection> sections = CategoryPickerSections.from(
      categories: categories,
      groups: groups,
    ).sections;
    return [
      for (final section in sections) ...[
        if (section.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ELayout.spaceMd,
              ELayout.spaceSm,
              ELayout.spaceMd,
              ELayout.spaceXs,
            ),
            child: Text(
              section.title!,
              style: EText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: FinanceColors.accentPrimary,
              ),
            ),
          ),
        for (final category in section.categories)
          MenuItemButton(
            onPressed: enabled ? () => onCategorySelected(category) : null,
            trailingIcon: category.id == selectedCategoryId
                ? const Icon(Icons.check, size: 16)
                : null,
            child: Text(category.name),
          ),
      ],
    ];
  }
}
