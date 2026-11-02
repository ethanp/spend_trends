import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Fixed-width cell so sibling rows share a column edge.
class const AppSpreadsheetCell({
  required final double width,
  required final Widget child,
  final Alignment alignment = Alignment.centerLeft,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(alignment: alignment, child: child),
    );
  }
}

/// Leading content + a shared-width trailing column (right-aligned).
///
/// Use the same [trailingWidth] across sibling rows so values form a column,
/// sized to the widest cell (see [StringsWidestLaidOutWidth.widestLaidOutWidth]).
class const AppSpreadsheetRow({
  required final Widget leading,
  required final Widget trailing,
  required final double trailingWidth,
  final double gap = ELayout.spaceMd,
  final CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Expanded(child: leading),
        SizedBox(width: gap),
        AppSpreadsheetCell(
          width: trailingWidth,
          alignment: Alignment.centerRight,
          child: trailing,
        ),
      ],
    );
  }
}
