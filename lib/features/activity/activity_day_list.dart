import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/rule_match_index.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/activity_column_widths.dart';
import 'package:spend_trends/features/activity/activity_transaction_tile.dart';

/// Day-grouped Activity transaction list (sliver).
class const ActivityDayListSliver({
  required final List<BankTransaction> transactions,
  required final Map<String, Account> accounts,
  required final Map<String, SpendCategory> categories,
  required final RuleMatchIndex ruleMatchIndex,
  required final Map<String, CategorizationRule?> explainingByTransactionId,
  required final String? selectedTransactionId,
  required final ActivityColumnWidths columnWidths,
  required final void Function(BankTransaction transaction)
  onTransactionSelected,
  required final void Function(CategorizationRule rule) onRuleSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final listItems = ActivityDayGrouping.items(transactions);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        0,
        ELayout.spaceLg,
        ELayout.spaceLg,
      ).withOverlaidTabBar(context),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final listItem = listItems[index];
          if (listItem is ActivityDayHeader) {
            return _ActivityDayHeaderTile(
              label: listItem.label,
              isFirst: index == 0,
            );
          }
          final transaction =
              (listItem as ActivityDayTransactionItem).transaction;
          final account = accounts[transaction.accountId];
          final category = categories[transaction.effectiveCategoryId];
          final explainingRule =
              explainingByTransactionId[transaction.id] ??
              ruleMatchIndex.explainingRule(transaction);
          return Padding(
            padding: const EdgeInsets.only(bottom: ELayout.spaceSm),
            child: ActivityTransactionTile(
              transaction: transaction,
              account: account,
              category: category,
              selected: selectedTransactionId == transaction.id,
              columnWidths: columnWidths,
              onActivated: () => onTransactionSelected(transaction),
              onRuleSelected:
                  explainingRule != null && explainingRule.beatsImportDefault
                  ? () => onRuleSelected(explainingRule)
                  : null,
            ),
          );
        }, childCount: listItems.length),
      ),
    );
  }
}

/// Groups transactions under Today / Yesterday / weekday headers.
class ActivityDayGrouping._() {
  static List<ActivityDayListItem> items(List<BankTransaction> transactions) {
    final today = DateTime.now().startOfDay;
    final yesterday = today.subtract(const Duration(days: 1));
    final listItems = <ActivityDayListItem>[];
    DateTime? currentDay;

    for (final transaction in transactions) {
      final day = transaction.postedAt.toLocal().startOfDay;
      if (currentDay != day) {
        currentDay = day;
        listItems.add(
          ActivityDayHeader(label: _dayHeaderLabel(day, today, yesterday)),
        );
      }
      listItems.add(ActivityDayTransactionItem(transaction: transaction));
    }
    return listItems;
  }

  static String _dayHeaderLabel(
    DateTime day,
    DateTime today,
    DateTime yesterday,
  ) {
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    if (day.year == today.year) {
      return DateFormat('EEEE, MMM d').format(day);
    }
    return DateFormat('EEEE, MMM d, y').format(day);
  }
}

sealed class const ActivityDayListItem();

class const ActivityDayHeader({required final String label})
    extends ActivityDayListItem;

class const ActivityDayTransactionItem({
  required final BankTransaction transaction,
}) extends ActivityDayListItem;

class const _ActivityDayHeaderTile({
  required final String label,
  required final bool isFirst,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: isFirst ? ELayout.spaceXs : ELayout.spaceLg,
        bottom: ELayout.spaceSm,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: EText.body.medium.copyWith(
              fontWeight: FontWeight.w600,
              color: EColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: ELayout.spaceMd),
          Expanded(child: Container(height: 1, color: EColors.border)),
        ],
      ),
    );
  }
}
