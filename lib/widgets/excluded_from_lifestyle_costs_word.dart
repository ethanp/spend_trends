import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Muted “excluded” beside a rule or transaction left out of lifestyle costs.
class const ExcludedFromLifestyleCostsWord() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Excluded from lifestyle costs',
      child: Padding(
        padding: const EdgeInsets.only(left: ELayout.spaceXs),
        child: Text(
          'excluded',
          style: EText.caption.copyWith(color: EColors.textMuted),
        ),
      ),
    );
  }
}
