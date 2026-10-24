import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/activity_column_widths.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/util/category_color.dart';
import 'package:spend_trends/widgets/transaction_list_row.dart';

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
  @override
  Widget build(BuildContext context) {
    final categoryColor = CategoryColor.forCategoryId(
      category?.id,
      categoryName: category?.name,
      groupId: category?.groupId,
    );
    final merchantName = transaction.rawDescription.isEmpty
        ? transaction.normalizedMerchant
        : transaction.rawDescription;

    return TransactionListRow(
      categoryColor: categoryColor,
      title: merchantName,
      amountCents: transaction.amountCents,
      amountColor: _amountColor,
      selected: selected,
      onActivated: onActivated,
      leadingCells: [
        TransactionListRow.cell(
          width: columnWidths.category,
          child: Text(
            categoryCaption ?? category?.name ?? 'Uncategorized',
            style: EText.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: categoryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TransactionListRow.cell(
          width: columnWidths.account,
          child: Text(
            account?.displayNameWithInstitution ?? '—',
            style: EText.caption.copyWith(color: EColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      trailing: _trailing(),
    );
  }

  Widget? _trailing() {
    final statusIcons = _statusIcons();
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
    if (statusIcons == null && ruleButton == null && extraTrailing == null) {
      return null;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?statusIcons,
        if (statusIcons != null &&
            (ruleButton != null || extraTrailing != null))
          const SizedBox(width: ELayout.spaceXs),
        ?ruleButton,
        if (ruleButton != null && extraTrailing != null)
          const SizedBox(width: ELayout.spaceXs),
        ?extraTrailing,
      ],
    );
  }

  Widget? _statusIcons() {
    if (!transaction.pending &&
        !transaction.excluded &&
        transaction.recurringSeries == null) {
      return null;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
