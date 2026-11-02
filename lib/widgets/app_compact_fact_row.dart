import 'package:ethan_ui/ethan_ui.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:flutter/material.dart';

/// Soft card fill/border pulled toward [tint] over metal surface.
BoxDecoration appTintedCardDecoration({
  required Color tint,
  bool selected = false,
}) {
  final fillAlpha = selected ? 0.22 : 0.12;
  final borderAlpha = selected ? 0.55 : 0.35;
  return BoxDecoration(
    color: Color.alphaBlend(tint.withValues(alpha: fillAlpha), EColors.surface),
    borderRadius: ELayout.borderRadiusMd,
    border: Border.all(
      color: tint.withValues(alpha: borderAlpha),
      width: selected ? 1.5 : 1,
    ),
  );
}

/// Compact horizontal fact columns — title capped with ellipsis; amount hugs.
///
/// Does not stretch title and amount to opposite edges of a wide window.
/// Pass the same [titleWidth] and [amountWidth] across sibling rows so cards
/// share one width (the widest label) and amounts stay aligned.
class const AppCompactFactRow({
  required final String title,
  final Widget? leading,
  final String? caption,

  /// Under the caption, inside the title column (e.g. a figures strip).
  final Widget? detail,
  final Widget? amount,
  final double? amountWidth,
  final Widget? trailing,
  final double? titleWidth,
  final double titleMaxWidth = 260,
  final Color? tintColor,
  final bool selected = false,

  /// When false, renders only the compact columns (caller owns chrome).
  final bool decorate = true,
  final VoidCallback? onActivated,
  final EdgeInsetsGeometry padding = const EdgeInsets.all(ELayout.spaceMd),
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: ELayout.spaceMd),
          ],
          ConstrainedBox(
            constraints: titleWidth == null
                ? BoxConstraints(maxWidth: titleMaxWidth)
                : BoxConstraints.tightFor(width: titleWidth),
            child: _titleColumn(),
          ),
          if (amount != null) ...[
            const SizedBox(width: ELayout.spaceMd),
            if (amountWidth != null)
              SizedBox(
                width: amountWidth,
                child: Align(alignment: Alignment.centerRight, child: amount),
              )
            else
              amount!,
          ],
          if (trailing != null) ...[
            const SizedBox(width: ELayout.spaceSm),
            trailing!,
          ],
        ],
      ),
    );

    final Widget body;
    if (!decorate) {
      body = row;
    } else if (tintColor != null) {
      body = Container(
        decoration: appTintedCardDecoration(
          tint: tintColor!,
          selected: selected,
        ),
        child: row,
      );
    } else {
      body = ESurface(
        kind: selected ? ESurfaceKind.tinted : ESurfaceKind.row,
        accent: selected ? FinanceColors.accentPrimary : null,
        child: row,
      );
    }

    if (onActivated == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onActivated,
      child: body,
    );
  }

  Widget _titleColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: EText.section.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (caption != null)
          Text(
            caption!,
            style: EText.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (detail != null) ...[
          const SizedBox(height: ELayout.spaceXs),
          detail!,
        ],
      ],
    );
  }
}
