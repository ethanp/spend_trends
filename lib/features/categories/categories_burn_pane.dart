import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_spend_pace.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';

import 'categories_providers.dart';
import 'category_spend_windows_row.dart';
import 'rule_match_caption_line.dart';

class const CategoriesBurnPane({
  required final String? selectedCategoryId,
  required final Map<String, SpendCategory> categoriesById,
  required final Map<String, CategorySpendPace> pacesByCategoryId,
  required final void Function(SpendCategory category) onCategoryOpened,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = selectedCategoryId == null
        ? null
        : categoriesById[selectedCategoryId];
    return ListView(
      padding: ETabBarOverlay.paddingOf(context),
      children: [
        if (selected == null)
          _burnOverview()
        else
          _categoryDetail(ref, selected),
      ],
    );
  }

  int get _totalBurnCents {
    var total = 0;
    for (final entry in pacesByCategoryId.entries) {
      if (SpecialCategory.isFlowId(entry.key)) continue;
      total += entry.value.oneYearAnnualCents;
    }
    return total;
  }

  Widget _burnOverview() {
    final totalBurn = _totalBurnCents;
    final ranked =
        [
          for (final entry in pacesByCategoryId.entries)
            if (!SpecialCategory.isFlowId(entry.key) &&
                entry.value.oneYearAnnualCents > 0)
              entry.value,
        ]..sort(
          (left, right) =>
              right.oneYearAnnualCents.compareTo(left.oneYearAnnualCents),
        );
    final top = ranked.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Annual burn', style: EText.section),
        const SizedBox(height: ELayout.spaceSm),
        Text(totalBurn == 0 ? '—' : formatCents(totalBurn), style: EText.title),
        Text('/ yr across spend categories', style: EText.caption),
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Top burn lines',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        if (top.isEmpty)
          Text('No annualized spend yet.', style: EText.caption)
        else
          for (final row in top) ...[
            Text(
              totalBurn == 0
                  ? row.categoryName
                  : '${row.categoryName} · '
                        '${_percentOf(row.oneYearAnnualCents, totalBurn)} · '
                        '${formatCents(row.oneYearAnnualCents)} / yr',
              style: EText.body.medium,
            ),
            const SizedBox(height: ELayout.spaceXs),
          ],
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'This burn rate is what future FI timelines will use — '
          'select a category to see its share.',
          style: EText.caption,
        ),
      ],
    );
  }

  Widget _categoryDetail(WidgetRef ref, SpendCategory category) {
    final CategorySpendPace? spendPace = pacesByCategoryId[category.id];
    final int annual = spendPace?.oneYearAnnualCents ?? 0;
    final totalBurn = _totalBurnCents;
    final rules =
        ref.watch(categorizationRulesProvider).asData?.value ??
        const <CategorizationRule>[];
    final categoryRules = [
      for (final rule in rules)
        if (rule.categoryId == category.id) rule,
    ];

    final builtInCaption = category.builtInCaption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(category.name, style: EText.section),
        if (builtInCaption != null) ...[
          const SizedBox(height: ELayout.spaceXs),
          Text(builtInCaption, style: EText.caption),
        ],
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Average spend per month',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceXs),
        CategorySpendWindowsRow(
          monthlyCents: (window) => spendPace?.monthlyCents(window) ?? 0,
        ),
        const SizedBox(height: ELayout.spaceMd),
        Text(
          '1y annual pace',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceXs),
        Text(
          annual == 0 ? '—' : '${formatCents(annual)} / yr',
          style: EText.section.copyWith(fontWeight: FontWeight.w600),
        ),
        if (!category.isFlow && totalBurn > 0) ...[
          const SizedBox(height: ELayout.spaceXs),
          Text(
            '${_percentOf(annual, totalBurn)} of annual burn',
            style: EText.caption,
          ),
        ],
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Rules',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceXs),
        if (categoryRules.isEmpty)
          Text('No merchant rules yet.', style: EText.caption)
        else ...[
          Text(
            categoryRules.length == 1
                ? '1 rule'
                : '${categoryRules.length} rules',
            style: EText.body.medium,
          ),
          for (final rule in categoryRules) RuleMatchCaptionLine(rule: rule),
        ],
        const SizedBox(height: ELayout.spaceLg),
        AppPrimaryButton(
          onPressed: () => onCategoryOpened(category),
          child: const Text('Edit'),
        ),
      ],
    );
  }

  String _percentOf(int part, int whole) {
    if (whole <= 0) return '0%';
    final pct = ((part / whole) * 100).round();
    return '$pct%';
  }
}
