import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/theme/finance_colors.dart';

import 'trends_providers.dart';

/// yr/mo/day chips that set the display rate for everything on Trends.
class const TrendSpendRateToggle() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrendSpendRate spendRate = ref.watch(trendSpendRateProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final rate in TrendSpendRate.values) ...[
          if (rate != TrendSpendRate.values.first)
            const SizedBox(width: ELayout.spaceXs),
          _rateChip(
            label: rate.toggleLabel,
            isSelected: spendRate == rate,
            onActivated: () =>
                ref.read(trendSpendRateProvider.notifier).setRate(rate),
          ),
        ],
      ],
    );
  }

  Widget _rateChip({
    required String label,
    required bool isSelected,
    required VoidCallback onActivated,
  }) {
    return GestureDetector(
      onTap: onActivated,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ELayout.spaceSm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? FinanceColors.accentPrimary.withValues(alpha: 0.25)
              : EColors.surface,
          borderRadius: ELayout.borderRadiusSm,
          border: Border.all(
            color: isSelected ? FinanceColors.accentPrimary : EColors.border,
          ),
        ),
        child: Text(
          label,
          style: EText.caption.copyWith(
            color: isSelected ? FinanceColors.accentPrimary : EColors.textMuted,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
