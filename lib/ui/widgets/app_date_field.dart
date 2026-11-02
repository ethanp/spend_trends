import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Tappable labeled date row that opens the app date picker flow.
class const AppDateField({
  required final String label,
  required final DateTime date,
  required final VoidCallback onActivated,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onActivated,
      child: Container(
        padding: const EdgeInsets.all(ELayout.spaceMd),
        decoration: BoxDecoration(
          color: EColors.surface,
          borderRadius: ELayout.borderRadiusSm,
          border: Border.all(color: EColors.border),
        ),
        child: Row(
          children: [
            Text(label, style: EText.body.medium),
            const Spacer(),
            Text(
              DateFormat.yMMMd().format(date),
              style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: ELayout.spaceSm),
            const Icon(
              Icons.calendar_today,
              size: 18,
              color: EColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
