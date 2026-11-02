import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Elevated bottom-sheet surface used by modal popups.
///
/// Tall panels pass [heightFraction] (typically `0.85`). Omit it for a
/// content-sized compact panel. Keyboard inset padding is on by default.
class AppSheetPanel extends StatelessWidget {
  const new({
    required this.child,
    this.heightFraction = 0.85,
    this.padForKeyboard = true,
  });

  /// Content-sized panel (no fixed viewport fraction).
  const new compact({required this.child, this.padForKeyboard = true})
    : heightFraction = null;

  final Widget child;

  /// Fraction of screen height for a tall panel; `null` wraps content height.
  final double? heightFraction;

  /// Pads the bottom by [MediaQuery.viewInsets] so fields clear the keyboard.
  final bool padForKeyboard;

  @override
  Widget build(BuildContext context) {
    final bottomInset = padForKeyboard
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    return Container(
      height: heightFraction == null
          ? null
          : MediaQuery.sizeOf(context).height * heightFraction!,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        gradient: EColors.metalPanelGradient,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ELayout.radiusLg),
        ),
        border: Border(top: BorderSide(color: EColors.frostBorder)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}
