import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Which pane has a fixed (draggable) width; the other expands.
enum AppBrowseSplitSizedSide() {
  left,
  right,
}

/// Auto-grow policy for a left-sized split as the window widens.
///
/// Phase 1: grow left until [leftComfortWidth] (right stays at minimum).
/// Phase 2: grow right until [rightComfortWidth] (left stays at comfort).
/// Phase 3: grow left again (right stays at its comfort).
class const AppBrowseSplitGrowth({
  required final double leftComfortWidth,
  required final double rightComfortWidth,
});

/// Wide-layout browse: one sized pane + one expanding pane.
///
/// Below [breakpoint] only [left] is shown (phone / narrow window).
/// Drag the divider to resize the sized pane.
class const AppBrowseSplitShell({
  required final Widget left,
  required final Widget right,
  final double breakpoint = 900,
  final AppBrowseSplitSizedSide sizedSide = AppBrowseSplitSizedSide.right,
  final double initialSizedWidth = 320,

  /// Caps the sized pane. When null, a right-sized pane uses [maxRightWidth]
  /// and 40% of the shell. A set value skips the 40% cap.
  final double? maxSizedWidth,

  /// When set with a left-sized pane, width follows [AppBrowseSplitGrowth]
  /// until the user drags the divider.
  final AppBrowseSplitGrowth? growth,
}) extends StatefulWidget {
  static const minRightWidth = 260.0;
  static const maxRightWidth = 480.0;
  static const minLeftWidth = 440.0;
  static const maxLeftWidth = 780.0;
  static const dividerHitWidth = 8.0;

  /// Whether [context] is currently in split (wide) mode.
  static bool isSplit(BuildContext context, {double breakpoint = 900}) {
    return MediaQuery.sizeOf(context).width >= breakpoint;
  }

  @override
  State<AppBrowseSplitShell> createState() => _AppBrowseSplitShellState();
}

class _AppBrowseSplitShellState() extends State<AppBrowseSplitShell> {
  final _shellKey = GlobalKey();
  late double _sizedWidth = widget.initialSizedWidth;
  bool _userDragged = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < widget.breakpoint) return widget.left;

        final sizedWidth = _resolveSizedWidth(constraints.maxWidth);
        final sizedChild = SizedBox(
          width: sizedWidth,
          child: widget.sizedSide == AppBrowseSplitSizedSide.left
              ? widget.left
              : widget.right,
        );
        final expandedChild = Expanded(
          child: widget.sizedSide == AppBrowseSplitSizedSide.left
              ? widget.right
              : widget.left,
        );

        return Row(
          key: _shellKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.sizedSide == AppBrowseSplitSizedSide.left) ...[
              sizedChild,
              _ResizeDivider(onDragAt: _setSizedWidthFromPointer),
              expandedChild,
            ] else ...[
              expandedChild,
              _ResizeDivider(onDragAt: _setSizedWidthFromPointer),
              sizedChild,
            ],
          ],
        );
      },
    );
  }

  void _setSizedWidthFromPointer(Offset globalPosition) {
    final box = _shellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final localX = box.globalToLocal(globalPosition).dx;
    final proposed = widget.sizedSide == AppBrowseSplitSizedSide.left
        ? localX
        : box.size.width - localX;
    setState(() {
      _userDragged = true;
      _sizedWidth = _clampToAvailable(box.size.width, proposed);
    });
  }

  double _resolveSizedWidth(double totalWidth) {
    final growth = widget.growth;
    if (widget.sizedSide == AppBrowseSplitSizedSide.left &&
        !_userDragged &&
        growth != null) {
      return _leftWidthForGrowth(totalWidth, growth);
    }

    return _clampToAvailable(totalWidth, _sizedWidth);
  }

  /// Three-phase left width as [totalWidth] increases.
  double _leftWidthForGrowth(double totalWidth, AppBrowseSplitGrowth growth) {
    const divider = AppBrowseSplitShell.dividerHitWidth;
    const minRight = AppBrowseSplitShell.minRightWidth;
    const minLeft = AppBrowseSplitShell.minLeftWidth;
    final leftComfort = math.max(minLeft, growth.leftComfortWidth);
    final rightComfort = math.max(minRight, growth.rightComfortWidth);
    final maxLeft = totalWidth - minRight - divider;
    if (maxLeft <= minLeft) return minLeft;

    final phase1End = leftComfort + minRight + divider;
    if (totalWidth <= phase1End) {
      return (totalWidth - minRight - divider).clamp(minLeft, maxLeft);
    }

    final phase2End = leftComfort + rightComfort + divider;
    if (totalWidth <= phase2End) {
      return leftComfort.clamp(minLeft, maxLeft);
    }

    return (totalWidth - rightComfort - divider).clamp(minLeft, maxLeft);
  }

  double _clampToAvailable(double totalWidth, double proposed) {
    final maxSized = _maxSizedWidth(totalWidth);
    final minSized = widget.sizedSide == AppBrowseSplitSizedSide.left
        ? AppBrowseSplitShell.minLeftWidth
        : AppBrowseSplitShell.minRightWidth;
    return proposed.clamp(minSized, math.max(minSized, maxSized));
  }

  double _maxSizedWidth(double totalWidth) {
    if (widget.sizedSide == AppBrowseSplitSizedSide.left) {
      return totalWidth -
          AppBrowseSplitShell.minRightWidth -
          AppBrowseSplitShell.dividerHitWidth;
    }

    final maxForLeft =
        totalWidth -
        AppBrowseSplitShell.minLeftWidth -
        AppBrowseSplitShell.dividerHitWidth;
    final cap = widget.maxSizedWidth ?? AppBrowseSplitShell.maxRightWidth;
    if (widget.maxSizedWidth != null) {
      return math.min(cap, maxForLeft);
    }
    return math.min(cap, math.min(totalWidth * 0.4, maxForLeft));
  }
}

class const _ResizeDivider({
  required final void Function(Offset globalPosition) onDragAt,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDragAt(details.globalPosition),
        child: SizedBox(
          width: AppBrowseSplitShell.dividerHitWidth,
          child: Center(child: Container(width: 1, color: EColors.border)),
        ),
      ),
    );
  }
}
