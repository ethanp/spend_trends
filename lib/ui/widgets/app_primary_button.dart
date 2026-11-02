import 'package:flutter/material.dart';

/// App primary (filled) action button; shows a spinner while [busy].
class const AppPrimaryButton({
  final bool busy = false,
  required final VoidCallback? onPressed,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : child,
    );
  }
}
