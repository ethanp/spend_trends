import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Compact (?) control that shows [message] on hover.
class const HelpTooltip({required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 250),
      child: const Icon(Icons.help_outline, size: 14, color: EColors.textMuted),
    );
  }
}
