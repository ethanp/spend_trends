import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/ui/widgets/excluded_from_lifestyle_costs_word.dart';

/// One rule in a category's rule list: what it matches, and “excluded” when
/// it leaves its rows out of lifestyle costs.
class const RuleMatchCaptionLine({required final CategorizationRule rule})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(child: Text(rule.matchCaption, style: EText.caption)),
        if (rule.excludesFromLifestyleCosts)
          const ExcludedFromLifestyleCostsWord(),
      ],
    );
  }
}
