import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/canceling_merchant_pairs.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/rule_match_index.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/activity_column_widths.dart';
import 'package:spend_trends/features/activity/activity_day_list.dart';
import 'package:spend_trends/features/activity/activity_transaction_tile.dart';
import 'package:spend_trends/features/activity/manage_rule_sheet.dart';
import 'package:spend_trends/features/activity/recategorize_sheet.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/widgets/app_browse_split_shell.dart';
import 'package:spend_trends/widgets/app_card.dart';

import 'banks_providers.dart';

/// Interactive transaction list for one pull import window.
class const BanksPullTransactionList({
  required final List<BankTransaction> transactions,
  required final String? selectedTransactionId,
  required final void Function(BankTransaction transaction)
  onTransactionSelected,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<BanksPullTransactionList> createState() =>
      _BanksPullTransactionListState();
}

class _BanksPullTransactionListState()
    extends ConsumerState<BanksPullTransactionList> {
  bool _hideOffsettingPairs = true;
  bool _uncategorizedOnly = false;

  @override
  Widget build(BuildContext context) {
    final Map<String, Account> accounts =
        ref.watch(accountsMapProvider).asData?.value ?? {};
    final categories = {
      for (final category
          in ref.watch(categoriesListProvider).asData?.value ??
              <SpendCategory>[])
        category.id: category,
    };
    final List<CategorizationRule> rules =
        ref.watch(categorizationRulesProvider).asData?.value ??
        const <CategorizationRule>[];

    final visible = _visibleTransactions(
      accounts: accounts,
      categories: categories,
      rules: rules,
    );
    final offsettingIds = CancelingMerchantPairs.transactionIds(
      widget.transactions,
      investmentAccountIds: CancelingMerchantPairs.investmentIdsFrom(accounts),
    );
    final ruleMatchIndex = RuleMatchIndex(rules);
    final explainingByTransactionId = ruleMatchIndex
        .explainingRulesByTransactionId(visible);

    if (widget.transactions.isEmpty) {
      return AppCard(
        child: Text(
          'No new transactions in this pull yet.',
          style: EText.body.medium,
        ),
      );
    }

    final columnWidths = ActivityColumnWidths.measure(
      transactions: visible,
      accounts: accounts,
      categories: categories,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filterRow(
          totalCount: widget.transactions.length,
          visibleCount: visible.length,
          offsettingCount: offsettingIds.length,
        ),
        if (offsettingIds.isNotEmpty) ...[
          const SizedBox(height: ELayout.spaceSm),
          Text(
            _offsettingCaption(offsettingIds.length),
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
        ],
        const SizedBox(height: ELayout.spaceMd),
        if (visible.isEmpty)
          AppCard(
            child: Text(
              _uncategorizedOnly
                  ? 'No uncategorized transactions in this pull.'
                  : 'All transactions are hidden as offsetting pairs. '
                        'Turn off “Hide offsetting pairs” to see them.',
              style: EText.body.medium,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final allocatedWidths = columnWidths.allocate(
                constraints.maxWidth,
              );
              final listItems = ActivityDayGrouping.items(visible);
              return Column(
                children: [
                  for (var index = 0; index < listItems.length; index++) ...[
                    if (index > 0) const SizedBox(height: ELayout.spaceSm),
                    _listItem(
                      listItem: listItems[index],
                      accounts: accounts,
                      categories: categories,
                      columnWidths: allocatedWidths,
                      explainingByTransactionId: explainingByTransactionId,
                      ruleMatchIndex: ruleMatchIndex,
                      offsettingIds: offsettingIds,
                    ),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  List<BankTransaction> _visibleTransactions({
    required Map<String, Account> accounts,
    required Map<String, SpendCategory> categories,
    required List<CategorizationRule> rules,
  }) {
    var visible = [
      for (final transaction in widget.transactions)
        if (!transaction.isLinkedCopilotEnrichment(accounts)) transaction,
    ];
    if (_uncategorizedOnly) {
      visible = [
        for (final transaction in visible)
          if (transaction.isUncategorized) transaction,
      ];
    }
    if (_hideOffsettingPairs) {
      visible = CancelingMerchantPairs.excludingCancelingPairs(
        visible,
        accountsById: accounts,
      );
    }
    return visible;
  }

  Widget _filterRow({
    required int totalCount,
    required int visibleCount,
    required int offsettingCount,
  }) {
    return Wrap(
      spacing: ELayout.spaceMd,
      runSpacing: ELayout.spaceSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$visibleCount of $totalCount transactions',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        FilterChip(
          label: const Text('Uncategorized only'),
          selected: _uncategorizedOnly,
          onSelected: (selected) =>
              setState(() => _uncategorizedOnly = selected),
        ),
        if (offsettingCount > 0)
          FilterChip(
            label: const Text('Hide offsetting pairs'),
            selected: _hideOffsettingPairs,
            onSelected: (selected) =>
                setState(() => _hideOffsettingPairs = selected),
          ),
      ],
    );
  }

  Widget _listItem({
    required ActivityDayListItem listItem,
    required Map<String, Account> accounts,
    required Map<String, SpendCategory> categories,
    required ActivityColumnWidths columnWidths,
    required Map<String, CategorizationRule?> explainingByTransactionId,
    required RuleMatchIndex ruleMatchIndex,
    required Set<String> offsettingIds,
  }) {
    if (listItem is ActivityDayHeader) {
      return Padding(
        padding: const EdgeInsets.only(top: ELayout.spaceSm),
        child: Text(
          listItem.label,
          style: EText.body.medium.copyWith(
            fontWeight: FontWeight.w600,
            color: EColors.textSecondary,
          ),
        ),
      );
    }

    final transaction = (listItem as ActivityDayTransactionItem).transaction;
    final account = accounts[transaction.accountId];
    final category = categories[transaction.effectiveCategoryId];
    final explainingRule =
        explainingByTransactionId[transaction.id] ??
        ruleMatchIndex.explainingRule(transaction);
    final isOffsetting = offsettingIds.contains(transaction.id);
    final String? categoryCaption =
        explainingRule != null &&
            explainingRule.beatsImportDefault &&
            category != null
        ? '${explainingRule.pattern} → ${category.name}'
        : null;

    return ActivityTransactionTile(
      transaction: transaction,
      account: account,
      category: category,
      categoryCaption: categoryCaption,
      selected: widget.selectedTransactionId == transaction.id,
      columnWidths: columnWidths,
      onActivated: () => _selectTransaction(transaction),
      onRuleSelected:
          explainingRule != null && explainingRule.beatsImportDefault
          ? () => ManageRuleSheet.show(context, ref: ref, rule: explainingRule)
          : null,
      extraTrailing: isOffsetting
          ? const Tooltip(
              message: 'Offsets another transaction in this pull',
              child: Icon(Icons.link, size: 15, color: EColors.textMuted),
            )
          : null,
    );
  }

  void _selectTransaction(BankTransaction transaction) {
    if (!AppBrowseSplitShell.isSplit(context)) {
      RecategorizeSheet.show(context, ref: ref, transaction: transaction);
      return;
    }
    widget.onTransactionSelected(transaction);
  }

  static String _offsettingCaption(int offsettingCount) {
    final pairCount = offsettingCount ~/ 2;
    return '$pairCount offsetting '
        '${pairCount == 1 ? 'pair' : 'pairs'} in this pull '
        '($offsettingCount transactions)';
  }
}
