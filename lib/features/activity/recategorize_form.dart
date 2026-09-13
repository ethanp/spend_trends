import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/contains_pattern_rematch.dart';
import 'package:spend_trends/features/activity/default_contains_pattern.dart';
import 'package:spend_trends/features/activity/existing_rule_overlaps.dart';
import 'package:spend_trends/features/activity/overlapping_merchant_contains_rules.dart';
import 'package:spend_trends/features/activity/rule_impact_match_row.dart';
import 'package:spend_trends/providers/spend_trends_providers.dart';
import 'package:spend_trends/widgets/category_picker.dart';
import 'package:spend_trends/widgets/select_all_none_row.dart';

/// Inline / sheet body for assigning a category (and optional contains-rule).
class const RecategorizeForm({
  required final BankTransaction transaction,

  /// Called after a successful category assign ([categoryId]) or note-only save
  /// (`null`).
  required final void Function(String? categoryId) onCompleted,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<RecategorizeForm> createState() => _RecategorizeFormState();
}

class _RecategorizeFormState() extends ConsumerState<RecategorizeForm> {
  bool _createRule = true;
  bool _savingNote = false;
  late final TextEditingController _patternController;
  late final TextEditingController _noteController;
  late final ContainsPatternRematch _patternRematch;
  final Set<String> _selectedMatchIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController(
      text: defaultContainsPattern(
        normalizedMerchant: widget.transaction.normalizedMerchant,
        rawDescription: widget.transaction.rawDescription,
      ),
    );
    _noteController = TextEditingController(
      text: widget.transaction.note ?? '',
    );
    _patternRematch = ContainsPatternRematch(
      fetchMatches: (pattern) async {
        final categorizer = await ref.read(categorizerProvider.future);
        return categorizer.transactionsMatchingContains(pattern);
      },
      notify: _selectRematchedTransactions,
    );
    _patternRematch.rematch(_patternController.text);
  }

  @override
  void dispose() {
    _patternRematch.dispose();
    _patternController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _selectRematchedTransactions() {
    if (!mounted) return;
    setState(() {
      if (_patternRematch.rematching) return;
      final previousIds = Set<String>.from(_selectedMatchIds);
      _selectedMatchIds
        ..removeAll(previousIds)
        ..addAll([
          for (final transaction in _patternRematch.matches) transaction.id,
        ]);
    });
  }

  String get _description => widget.transaction.rawDescription.isEmpty
      ? widget.transaction.normalizedMerchant
      : widget.transaction.rawDescription;

  bool get _noteDirty {
    final current = _noteController.text.trim();
    final original = (widget.transaction.note ?? '').trim();
    return current != original;
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesListProvider);
    final groupsAsync = ref.watch(categoryGroupsProvider);

    if (categoriesAsync.hasError && !categoriesAsync.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(ELayout.spaceLg),
        child: Text(
          '${categoriesAsync.error}',
          style: EText.body.medium.copyWith(color: EColors.danger),
        ),
      );
    }
    if (!categoriesAsync.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(ELayout.spaceXl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final categories = categoriesAsync.requireValue;
    final groups = groupsAsync.asData?.value ?? const <CategoryGroup>[];
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        ELayout.spaceLg,
        ELayout.spaceLg,
        ELayout.spaceMd,
      ).withOverlaidTabBar(context),
      children: [
        _formHeader(),
        const SizedBox(height: ELayout.spaceMd),
        _noteField(),
        const SizedBox(height: ELayout.spaceMd),
        _createRuleToggle(),
        if (_createRule) ...[
          const SizedBox(height: ELayout.spaceSm),
          _patternAndImpactPreview(),
        ],
        if (_error != null) ...[
          const SizedBox(height: ELayout.spaceSm),
          Text(_error!, style: EText.caption.copyWith(color: EColors.danger)),
        ],
        const SizedBox(height: ELayout.spaceLg),
        _categoryPicker(categories, groups),
      ],
    );
  }

  Widget _formHeader() {
    final dateLabel = DateFormat.yMMMd().format(
      widget.transaction.postedAt.toLocal(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Categorize', style: EText.section),
        const SizedBox(height: ELayout.spaceXs),
        Text(
          _description,
          style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: ELayout.spaceXs),
        Text(
          '${formatCents(widget.transaction.amountCents)} · $dateLabel',
          style: EText.caption,
        ),
      ],
    );
  }

  Widget _noteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Note', style: EText.caption),
        const SizedBox(height: ELayout.spaceXs),
        TextField(
          controller: _noteController,
          decoration: EInput.filledMd(hintText: 'Optional note'),
          maxLines: 3,
          minLines: 1,
          style: EText.body.medium.copyWith(color: EColors.textPrimary),
          onChanged: (_) => setState(() {}),
        ),
        if (_noteDirty) ...[
          const SizedBox(height: ELayout.spaceXs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _savingNote ? null : _saveNoteOnly,
              child: _savingNote
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save note'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _createRuleToggle() {
    return Row(
      children: [
        Switch(
          value: _createRule,
          onChanged: (value) {
            setState(() => _createRule = value);
            if (value) {
              _patternRematch.rematch(_patternController.text);
            }
          },
        ),
        const SizedBox(width: ELayout.spaceSm),
        Expanded(child: Text('Also create a rule', style: EText.body.medium)),
      ],
    );
  }

  Widget _patternAndImpactPreview() {
    final existingRules =
        ref.watch(categorizationRulesProvider).asData?.value ??
        const <CategorizationRule>[];
    final categories =
        ref.watch(categoriesListProvider).asData?.value ??
        const <SpendCategory>[];
    final categoryNameById = {
      for (final category in categories) category.id: category.name,
    };
    final related = overlappingMerchantContainsRules(
      candidatePattern: _patternController.text,
      existingRules: existingRules,
      categoryNameById: categoryNameById,
    );
    final matches = _patternRematch.matches;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('If description contains (ignore case)', style: EText.caption),
        const SizedBox(height: ELayout.spaceXs),
        TextField(
          controller: _patternController,
          decoration: EInput.filledMd(hintText: 'e.g. bbq'),
          style: EText.body.medium.copyWith(color: EColors.textPrimary),
          onChanged: (value) {
            setState(() {});
            _patternRematch.schedule(value);
          },
        ),
        const SizedBox(height: ELayout.spaceXs),
        Text(
          'Example: "bbq" → Dining matches “Franklin BBQ Austin”.',
          style: EText.caption,
        ),
        ExistingRuleOverlaps(overlaps: related),
        const SizedBox(height: ELayout.spaceMd),
        _matchPreviewHeader(matches.length),
        if (_patternRematch.rematching) ...[
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
        if (matches.isEmpty && !_patternRematch.rematching)
          Padding(
            padding: const EdgeInsets.only(top: ELayout.spaceSm),
            child: Text(
              'No existing transactions match this pattern.',
              style: EText.caption.copyWith(color: EColors.textMuted),
            ),
          ),
        const SizedBox(height: ELayout.spaceSm),
        for (final transaction in matches)
          RuleImpactMatchRow(
            transaction: transaction,
            currentCategoryName: RuleImpactMatchRow.categoryLabel(
              transaction,
              categoryNameById,
            ),
            selected: _selectedMatchIds.contains(transaction.id),
            onSelectionChanged: (selected) =>
                _setSelected(transaction.id, selected),
          ),
      ],
    );
  }

  Widget _matchPreviewHeader(int matchCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          matchCount == 0
              ? 'Matching transactions appear as you type. The rule still '
                    'applies to future matches.'
              : '$matchCount existing '
                    '${matchCount == 1 ? 'transaction matches' : 'transactions match'}. '
                    'Deselect any that should keep their current category.',
          style: EText.caption,
        ),
        if (matchCount > 0) ...[
          const SizedBox(height: ELayout.spaceXs),
          SelectAllNoneRow(
            onAllSelected: _selectAllMatches,
            onNoneSelected: _selectNoMatches,
          ),
        ],
      ],
    );
  }

  Widget _categoryPicker(
    List<SpendCategory> categories,
    List<CategoryGroup> groups,
  ) {
    return CategoryPicker(
      categories: categories,
      groups: groups,
      selectedId: widget.transaction.effectiveCategoryId,
      onCategorySelected: _assign,
    );
  }

  Future<void> _assign(SpendCategory category) async {
    if (!_validateRuleInput()) return;

    setState(() => _error = null);
    try {
      final alsoApplyToTransactionIds = _createRule
          ? Set<String>.from(_selectedMatchIds)
          : const <String>{};
      await _persistAssignment(category.id, alsoApplyToTransactionIds);
      if (mounted) widget.onCompleted(category.id);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  bool _validateRuleInput() {
    if (!_createRule || _patternController.text.trim().isNotEmpty) return true;
    setState(() => _error = 'Enter a contains pattern, or turn the rule off.');
    return false;
  }

  Future<void> _persistAssignment(
    String categoryId,
    Set<String> alsoApplyToTransactionIds,
  ) async {
    await _persistNoteIfNeeded();
    final categorizer = await ref.read(categorizerProvider.future);
    await categorizer.assignUserCategory(
      transactionId: widget.transaction.id,
      categoryId: categoryId,
      createRule: _createRule,
      containsPattern: _createRule ? _patternController.text.trim() : null,
      alsoApplyToTransactionIds: alsoApplyToTransactionIds,
    );
    ref.read(spendDataChangedProvider.notifier).notify();
  }

  Future<void> _saveNoteOnly() async {
    setState(() {
      _savingNote = true;
      _error = null;
    });
    try {
      await _persistNoteIfNeeded();
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) widget.onCompleted(null);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _persistNoteIfNeeded() async {
    if (!_noteDirty) return;
    final repository = await ref.read(transactionsRepositoryProvider.future);
    await repository.setNote(
      transactionId: widget.transaction.id,
      note: _noteController.text,
    );
  }

  void _setSelected(String transactionId, bool selected) {
    setState(() {
      if (selected) {
        _selectedMatchIds.add(transactionId);
      } else {
        _selectedMatchIds.remove(transactionId);
      }
    });
  }

  void _selectAllMatches() {
    setState(() {
      _selectedMatchIds
        ..clear()
        ..addAll([
          for (final transaction in _patternRematch.matches) transaction.id,
        ]);
    });
  }

  void _selectNoMatches() {
    setState(_selectedMatchIds.clear);
  }
}
