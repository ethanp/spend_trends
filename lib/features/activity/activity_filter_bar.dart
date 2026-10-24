import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/widgets/app_card.dart';

/// Sticky Activity chrome: search and uncategorized-only.
class const ActivityFilterBar({
  required final TextEditingController searchController,
  required final ValueChanged<String> onSearchChanged,
  required final bool uncategorizedOnly,
  required final int searchMatchCount,
  required final int visibleCount,
  required final ValueChanged<bool> onUncategorizedOnlyChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EColors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ELayout.spaceLg,
          ELayout.spaceLg,
          ELayout.spaceLg,
          ELayout.spaceSm,
        ),
        child: Column(
          children: [
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: EInput.filledMd(
                hintText: 'Search description, category, account…',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: ELayout.spaceSm),
            _UncategorizedOnlyToggle(
              uncategorizedOnly: uncategorizedOnly,
              hiddenCount: searchMatchCount - visibleCount,
              visibleCount: visibleCount,
              onChanged: onUncategorizedOnlyChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class const _UncategorizedOnlyToggle({
  required final bool uncategorizedOnly,
  required final int hiddenCount,
  required final int visibleCount,
  required final ValueChanged<bool> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: ELayout.spaceMd,
        vertical: ELayout.spaceSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uncategorized only',
                  style: EText.body.medium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  uncategorizedOnly
                      ? '$visibleCount need a rule · $hiddenCount categorized'
                      : 'Showing all loaded transactions',
                  style: EText.caption,
                ),
              ],
            ),
          ),
          Switch(value: uncategorizedOnly, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Sum of the currently visible Activity list (right-pane chrome).
class const ActivityVisibleSumBar({
  required final List<BankTransaction> visibleTransactions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var netCents = 0;
    var inflowCents = 0;
    var outflowCents = 0;
    for (final transaction in visibleTransactions) {
      netCents += transaction.amountCents;
      if (transaction.isInflow) {
        inflowCents += transaction.amountCents;
      } else if (transaction.isOutflow) {
        outflowCents += transaction.amountCents;
      }
    }

    final netColor = netCents > 0
        ? EColors.success
        : netCents < 0
        ? EColors.danger
        : EColors.textSecondary;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: ELayout.spaceMd,
        vertical: ELayout.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sum visible list',
            style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: ELayout.spaceXs),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${visibleTransactions.length} '
                  '${visibleTransactions.length == 1 ? 'transaction' : 'transactions'}',
                  style: EText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: ELayout.spaceMd),
              Text(
                formatCents(netCents),
                style: EText.section.copyWith(color: netColor),
                maxLines: 1,
              ),
            ],
          ),
          if (inflowCents != 0 || outflowCents != 0) ...[
            const SizedBox(height: ELayout.spaceXs),
            Text(
              'In ${formatCents(inflowCents)} · Out ${formatCents(outflowCents)}',
              style: EText.caption,
            ),
          ],
        ],
      ),
    );
  }
}
