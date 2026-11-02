import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Whether a rule excludes what it categorizes from lifestyle costs; those
/// rows keep their category.
class const ExcludeFromLifestyleCostsSwitch({
  required final bool excludes,

  /// Null disables the switch (e.g. while a change is saving).
  required final ValueChanged<bool>? onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Switch(value: excludes, onChanged: onChanged),
        const SizedBox(width: ELayout.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Exclude from lifestyle costs', style: EText.body.medium),
              const SizedBox(height: ELayout.spaceXs),
              Text(
                'Keeps the category but leaves its rows out of Fixed costs, '
                'Guilt-free, and the FIRE baseline.',
                style: EText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
