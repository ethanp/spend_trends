import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/categories/category_spend_pace.dart';

/// Average monthly spend over 2y · 1y · 6mo · 3mo, window label over amount.
/// Fixed cell widths keep the windows aligned down a list of cards.
class const CategorySpendWindowsRow({
  required final int Function(CategorySpendWindow window) monthlyCents,
  final bool emphasized = true,
}) extends StatelessWidget {
  static const cellWidth = 48.0;
  static const width = cellWidth * 4;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final window in CategorySpendWindow.values)
          SizedBox(width: cellWidth, child: _windowCell(window)),
      ],
    );
  }

  Widget _windowCell(CategorySpendWindow window) {
    final int cents = monthlyCents(window);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          window.label,
          style: EText.caption.copyWith(color: EColors.textMuted, fontSize: 10),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            cents == 0 ? '—' : formatCentsWholeDollars(cents),
            maxLines: 1,
            style: (emphasized ? EText.body.small : EText.caption).copyWith(
              color: EColors.textPrimary,
              fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
