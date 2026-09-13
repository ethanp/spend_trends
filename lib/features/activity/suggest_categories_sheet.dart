import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/features/activity/rule_impact_confirm_sheet.dart';
import 'package:spend_trends/providers/llm_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/llm/llm_errors.dart';
import 'package:spend_trends/services/llm/suggest_merchant_categories.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

class const SuggestCategoriesSheet() extends ConsumerStatefulWidget {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SuggestCategoriesSheet(),
    );
  }

  @override
  ConsumerState<SuggestCategoriesSheet> createState() =>
      _SuggestCategoriesSheetState();
}

class _SuggestCategoriesSheetState()
    extends ConsumerState<SuggestCategoriesSheet> {
  bool _loading = true;
  bool _createRules = true;
  String? _error;
  List<CategorySuggestion> _suggestions = const [];

  String get _primaryActionLabel => _createRules ? 'Review' : 'Apply';

  String get _bulkActionLabel => _createRules ? 'Review all' : 'Apply all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadSuggestions();
    } on LlmException catch (error) {
      _showLoadError(error.message);
    } catch (error) {
      _showLoadError('$error');
    }
  }

  Future<void> _loadSuggestions() async {
    final suggester = await ref.read(suggestMerchantCategoriesProvider.future);
    if (suggester == null) {
      _showLoadError(
        'Configure LLM_APP_SECRET and SERVER_HOST_LAN in .env to use suggestions.',
      );
      return;
    }

    final suggestions = await suggester.forUncategorizedMerchants();
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _loading = false;
    });
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetPanel(
      heightFraction: 0.7,
      padForKeyboard: false,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(ELayout.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(),
          const SizedBox(height: ELayout.spaceMd),
          _buildCreateRulesToggle(),
          if (_createRules) ...[
            const SizedBox(height: ELayout.spaceXs),
            Text(
              'You’ll confirm which existing transactions each rule '
              'should update.',
              style: EText.caption,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTitleRow() {
    return Row(
      children: [
        Expanded(child: Text('Suggested categories', style: EText.section)),
        if (_suggestions.isNotEmpty)
          TextButton(onPressed: _reviewAll, child: Text(_bulkActionLabel)),
      ],
    );
  }

  Widget _buildCreateRulesToggle() {
    return Row(
      children: [
        Switch(
          value: _createRules,
          onChanged: (value) => setState(() => _createRules = value),
        ),
        const SizedBox(width: ELayout.spaceSm),
        Expanded(
          child: Text(
            'Also create a rule for each merchant',
            style: EText.body.medium,
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(ELayout.spaceLg),
        child: Text(
          _error!,
          style: EText.body.medium.copyWith(color: EColors.danger),
        ),
      );
    }
    if (_suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(ELayout.spaceLg),
        child: Text(
          'Nothing uncategorized to suggest.',
          style: EText.body.medium,
        ),
      );
    }
    return _buildSuggestionList();
  }

  Widget _buildSuggestionList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceLg),
      itemCount: _suggestions.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: ELayout.spaceSm),
      itemBuilder: (context, index) => _buildSuggestionRow(_suggestions[index]),
    );
  }

  Widget _buildSuggestionRow(CategorySuggestion suggestion) {
    return ESurface(
      kind: ESurfaceKind.row,
      padding: const EdgeInsets.all(ELayout.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.merchant,
                  style: EText.section.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  suggestion.createsCategory
                      ? 'New · ${suggestion.categoryName}'
                      : suggestion.categoryName,
                  style: suggestion.createsCategory
                      ? EText.caption.copyWith(
                          color: FinanceColors.accentSecondary,
                        )
                      : EText.caption.copyWith(
                          color: FinanceColors.accentPrimary,
                        ),
                ),
                if (suggestion.transactionAmountCents.isNotEmpty) ...[
                  const SizedBox(height: ELayout.spaceXs),
                  Text(
                    _amountsLabel(suggestion),
                    style: EText.body.medium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () => _reviewOne(suggestion),
            child: Text(_primaryActionLabel),
          ),
        ],
      ),
    );
  }

  static String _amountsLabel(CategorySuggestion suggestion) {
    final amounts = suggestion.transactionAmountCents;
    if (amounts.length == 1) return formatCents(amounts.first);
    if (amounts.length <= 3) {
      return amounts.map(formatCents).join(' · ');
    }
    return '${amounts.length} txns · ${formatCents(suggestion.totalAmountCents)}';
  }

  Future<void> _reviewAll() async {
    final applied = await _apply(_suggestions);
    if (applied && mounted) Navigator.of(context).pop();
  }

  Future<void> _reviewOne(CategorySuggestion suggestion) async {
    final applied = await _apply([suggestion]);
    if (!applied || !mounted) return;
    setState(() {
      _suggestions = _suggestions
          .where((item) => item.merchant != suggestion.merchant)
          .toList();
    });
  }

  /// Returns false if the user cancelled the rule-impact confirm sheet.
  Future<bool> _apply(List<CategorySuggestion> suggestions) async {
    final suggester = await ref.read(suggestMerchantCategoriesProvider.future);
    if (suggester == null) return false;

    final resolved = await suggester.createMissingCategories(suggestions);

    if (!_createRules) {
      await suggester.applyToUncategorized(resolved);
      ref.read(spendDataChangedProvider.notifier).notify();
      return true;
    }

    return _applyWithRules(resolved);
  }

  Future<bool> _applyWithRules(List<CategorySuggestion> suggestions) async {
    final categorizer = await ref.read(categorizerProvider.future);
    final groups = await _buildImpactGroups(categorizer, suggestions);
    if (!mounted) return false;

    final result = await RuleImpactConfirmSheet.show(context, groups: groups);
    if (result == null) return false;

    await _persistRulesAndCategories(
      categorizer,
      result.groups,
      result.selectedTransactionIds,
    );
    ref.read(spendDataChangedProvider.notifier).notify();
    return true;
  }

  Future<List<RuleImpactGroup>> _buildImpactGroups(
    Categorizer categorizer,
    List<CategorySuggestion> suggestions,
  ) async {
    final groups = <RuleImpactGroup>[];
    for (final suggestion in suggestions) {
      final pattern = suggestion.merchant.trim();
      final categoryId = suggestion.categoryId;
      if (pattern.isEmpty || categoryId == null) continue;
      groups.add(
        RuleImpactGroup(
          pattern: pattern,
          categoryId: categoryId,
          categoryName: suggestion.categoryName,
          transactions: await categorizer.transactionsMatchingContains(pattern),
        ),
      );
    }
    return groups;
  }

  Future<void> _persistRulesAndCategories(
    Categorizer categorizer,
    List<RuleImpactGroup> groups,
    Set<String> selectedIds,
  ) async {
    for (final group in groups) {
      await categorizer.upsertMerchantContainsRule(
        pattern: group.pattern,
        categoryId: group.categoryId,
      );
      await categorizer.applyCategoryToTransactions(
        categoryId: group.categoryId,
        transactionIds: [
          for (final transaction in group.transactions)
            if (selectedIds.contains(transaction.id)) transaction.id,
        ],
        asUserCategory: false,
      );
    }
  }
}
