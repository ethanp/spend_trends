import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/ui/activity/activity_column_widths.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';
import 'package:spend_trends/ui/theme/category_color.dart';
import 'package:spend_trends/ui/widgets/excluded_from_lifestyle_costs_word.dart';
import 'package:spend_trends/ui/widgets/transaction_list_row.dart';

/// One Activity row: [category | account | title | amount].
class const ActivityTransactionTile({
  required final BankTransaction transaction,
  required final Account? account,
  required final SpendCategory? category,
  required final VoidCallback onActivated,
  required final ActivityColumnWidths columnWidths,
  final VoidCallback? onRuleSelected,
  final bool selected = false,
  final Widget? extraTrailing,
  final String? categoryCaption,
}) extends StatelessWidget {
  static const copiedHeaderCells = [
    'Date',
    'Category',
    'Account',
    'Merchant',
    'Amount',
  ];

  @override
  Widget build(BuildContext context) {
    final categoryColor = CategoryColor.forCategoryId(
      category?.id,
      categoryName: category?.name,
    );
    final merchantName = transaction.rawDescription.isEmpty
        ? transaction.normalizedMerchant
        : transaction.rawDescription;

    final categoryLabel = categoryCaption ?? category?.name ?? 'Uncategorized';
    final accountLabel = account?.displayNameWithInstitution ?? '—';

    return ECopyableRow(
      cells: [
        DateFormat.yMMMd().format(transaction.postedDay.localMidnight),
        categoryLabel,
        accountLabel,
        merchantName,
        formatCents(transaction.amountCents),
      ],
      child: TransactionListRow(
        categoryColor: categoryColor,
        title: merchantName,
        amountCents: transaction.amountCents,
        amountColor: _amountColor,
        selected: selected,
        onActivated: onActivated,
        leadingCells: [
          SizedBox(
            width: columnWidths.category,
            child: Text(
              categoryLabel,
              style: EText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: categoryColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: columnWidths.account,
            child: Text(
              accountLabel,
              style: EText.caption.copyWith(color: EColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        trailing: _trailing(),
      ),
    );
  }

  Widget? _trailing() {
    final statusMarks = _statusMarks();
    final ruleButton = onRuleSelected == null
        ? null
        : Tooltip(
            message: 'Manage categorization rule',
            child: TextButton(
              onPressed: onRuleSelected,
              style: TextButton.styleFrom(
                foregroundColor: FinanceColors.accentPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: ELayout.spaceSm,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Rule',
                style: EText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: FinanceColors.accentPrimary,
                ),
              ),
            ),
          );
    if (statusMarks == null && ruleButton == null && extraTrailing == null) {
      return null;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?statusMarks,
        if (statusMarks != null &&
            (ruleButton != null || extraTrailing != null))
          const SizedBox(width: ELayout.spaceXs),
        ?ruleButton,
        if (ruleButton != null && extraTrailing != null)
          const SizedBox(width: ELayout.spaceXs),
        ?extraTrailing,
      ],
    );
  }

  Widget? _statusMarks() {
    if (!transaction.pending &&
        !transaction.excluded &&
        transaction.recurringSeries == null &&
        !transaction.excludedFromLifestyleCosts) {
      return null;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (transaction.excludedFromLifestyleCosts)
          const ExcludedFromLifestyleCostsWord(),
        if (transaction.pending)
          const Icon(Icons.schedule, size: 15, color: EColors.warning),
        if (transaction.excluded)
          const Icon(Icons.visibility_off, size: 15, color: EColors.danger),
        if (transaction.recurringSeries != null)
          const Icon(Icons.sync, size: 15, color: FinanceColors.accentPrimary),
      ],
    );
  }

  Color get _amountColor {
    if (category?.isTransfer == true) {
      return FinanceColors.accentSecondary;
    }
    if (category?.isAssetSale == true) return CategoryColor.assetSale;
    if (transaction.isInflow || category?.isIncome == true) {
      return EColors.success;
    }
    return EColors.danger;
  }
}
