import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/rule_change_plan.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/contains_pattern_rematch.dart';
import 'package:spend_trends/features/activity/default_contains_pattern.dart';
import 'package:spend_trends/features/activity/existing_rule_overlaps.dart';
import 'package:spend_trends/features/activity/overlapping_merchant_contains_rules.dart';
import 'package:spend_trends/features/activity/rule_impact_match_row.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:spend_trends/widgets/category_picker.dart';

/// Inline / sheet body for categorizing a transaction. Picking a category
/// always creates (or retargets) a rule; categories come only from rules.
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
  bool _limitRuleToThisAccount = false;
  bool _savingNote = false;
  late final TextEditingController _patternController;
  late final TextEditingController _noteController;
  late final ContainsPatternRematch _patternRematch;
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
        return categorizer.transactionsClaimedBy(
          _ruleDraft(
            pattern: pattern,
            categoryId: widget.transaction.categoryId ?? '',
          ),
        );
      },
      notify: () {
        if (mounted) setState(() {});
      },
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
      padding: ETabBarOverlay.paddingOf(
        context,
        contentPadding: const EdgeInsets.fromLTRB(
          ELayout.spaceLg,
          ELayout.spaceLg,
          ELayout.spaceLg,
          ELayout.spaceMd,
        ),
      ),
      children: [
        _formHeader(),
        const SizedBox(height: ELayout.spaceMd),
        _noteField(),
        const SizedBox(height: ELayout.spaceMd),
        _ruleAccountScopeToggle(
          ref.watch(accountsMapProvider).asData?.value ?? const {},
        ),
        const SizedBox(height: ELayout.spaceSm),
        _patternAndImpactPreview(),
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

  Widget _ruleAccountScopeToggle(Map<String, Account> accountsById) {
    final account = accountsById[widget.transaction.accountId];
    final accountLabel = account?.displayNameWithInstitution ?? 'This account';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Switch(
          value: _limitRuleToThisAccount,
          onChanged: (limited) {
            setState(() => _limitRuleToThisAccount = limited);
            _patternRematch.rematch(_patternController.text);
          },
        ),
        const SizedBox(width: ELayout.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Limit rule to one account', style: EText.body.medium),
              const SizedBox(height: ELayout.spaceXs),
              Text(
                _limitRuleToThisAccount ? 'Only $accountLabel' : 'Every account — turn on to scope (e.g. brokerage buy/sell).',
                style: EText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  RuleDraft _ruleDraft({required String pattern, required String categoryId}) =>
      RuleDraft(
        pattern: pattern,
        categoryId: categoryId,
        accountId: _limitRuleToThisAccount
            ? widget.transaction.accountId
            : null,
      );

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
          ),
      ],
    );
  }

  Widget _matchPreviewHeader(int matchCount) {
    return Text(
      matchCount == 0
          ? 'Transactions the rule would take appear as you type. It also '
                'applies to future ones.'
          : 'The rule takes these $matchCount existing '
                '${matchCount == 1 ? 'transaction' : 'transactions'}. '
                'Narrow the pattern or limit it to one account to leave any out.',
      style: EText.caption,
    );
  }

  Widget _categoryPicker(
    List<SpendCategory> categories,
    List<CategoryGroup> groups,
  ) {
    return CategoryPicker(
      categories: categories,
      groups: groups,
      selectedId: widget.transaction.categoryId,
      onCategorySelected: _assign,
    );
  }

  Future<void> _assign(SpendCategory category) async {
    if (!_validateRuleInput()) return;

    setState(() => _error = null);
    try {
      await _persistAssignment(category.id);
      if (mounted) widget.onCompleted(category.id);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  bool _validateRuleInput() {
    final pattern = _patternController.text.trim();
    final String? problem = pattern.isEmpty
        ? 'Enter a contains pattern.'
        : !_ruleDraft(
            pattern: pattern,
            categoryId: '',
          ).matches(widget.transaction)
        ? 'The pattern must match this transaction.'
        : null;
    setState(() => _error = problem);
    return problem == null;
  }

  Future<void> _persistAssignment(String categoryId) async {
    await _persistNoteIfNeeded();
    final categorizer = await ref.read(categorizerProvider.future);
    await categorizer.applyRuleChanges(
      drafts: [
        _ruleDraft(
          pattern: _patternController.text.trim(),
          categoryId: categoryId,
        ),
      ],
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
}
