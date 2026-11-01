import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/theme/finance_colors.dart';

/// Metal transaction row: category color bar | [leading cells…] | title |
/// amount | [trailing]. A selected row is tinted with the finance accent.
class const TransactionListRow({
  required final Color categoryColor,
  required final String title,
  required final int amountCents,
  required final Color amountColor,
  final List<Widget> leadingCells = const [],
  final Widget? trailing,
  final VoidCallback? onActivated,
  final bool selected = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ESurface(
      kind: selected ? ESurfaceKind.tinted : ESurfaceKind.row,
      accent: selected ? FinanceColors.accentPrimary : null,
      onActivated: onActivated,
      borderRadius: ELayout.borderRadiusMd,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _categoryColorBar(),
            Expanded(child: _cells()),
          ],
        ),
      ),
    );
  }

  Widget _categoryColorBar() =>
      SizedBox(width: 5, child: ColoredBox(color: categoryColor));

  Widget _cells() {
    return Padding(
      padding: const EdgeInsets.all(ELayout.spaceMd),
      child: Row(
        children: [
          for (final cell in leadingCells) ...[
            cell,
            const SizedBox(width: ELayout.spaceSm),
          ],
          Expanded(child: _title()),
          const SizedBox(width: ELayout.spaceMd),
          _amount(),
          if (trailing != null) ...[
            const SizedBox(width: ELayout.spaceSm),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _title() {
    return Text(
      title,
      style: EText.body.medium.copyWith(
        fontWeight: FontWeight.w600,
        color: EColors.textPrimary,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _amount() {
    return Text(
      formatCents(amountCents),
      style: EText.body.medium.copyWith(
        fontWeight: FontWeight.w600,
        color: amountColor,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 1,
    );
  }
}
