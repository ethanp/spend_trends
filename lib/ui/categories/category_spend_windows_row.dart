import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/categories/category_spend_pace.dart';

/// Average monthly spend over 2y · 1y · 6mo · 3mo as an inset strip: the
/// windows split the available width evenly, hairlines between them.
class const CategorySpendWindowsRow({
  required final int Function(CategorySpendWindow window) monthlyCents,
  final bool emphasized = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: ELayout.spaceSm),
      decoration: BoxDecoration(
        color: EColors.surfaceInset.withValues(alpha: emphasized ? 0.7 : 0.4),
        borderRadius: ELayout.borderRadiusMd,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final window in CategorySpendWindow.values) ...[
              if (window != CategorySpendWindow.values.first)
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: EColors.border,
                ),
              Expanded(child: _windowCell(window)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _windowCell(CategorySpendWindow window) {
    final int cents = monthlyCents(window);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceXs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            window.label,
            style: EText.caption.copyWith(
              color: EColors.textMuted,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              cents == 0 ? '—' : formatCentsWholeDollars(cents),
              maxLines: 1,
              style: (emphasized ? EText.body.small : EText.caption).copyWith(
                color: emphasized ? EColors.textPrimary : EColors.textTertiary,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
