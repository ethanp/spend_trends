import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';
import 'package:spend_trends/features/activity/recategorize_sheet.dart';
import 'package:spend_trends/features/trends/trend_point_contributors.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';
import 'package:spend_trends/widgets/app_spreadsheet.dart';

/// Modal listing the top transactions feeding a trendline at a tap date.
class const TrendPointContributorsSheet({
  required final String seriesName,
  required final DateTime tapDate,
  required final List<TrendPointContributor> contributors,

  /// Series smoothed value at [tapDate], annualized (/ yr).
  required final int linePaceCents,
}) extends ConsumerStatefulWidget {
  static const _contentMaxWidth = 720.0;

  static Future<void> show(
    BuildContext context, {
    required String seriesName,
    required DateTime tapDate,
    required List<TrendPointContributor> contributors,
    required int linePaceCents,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TrendPointContributorsSheet(
        seriesName: seriesName,
        tapDate: tapDate,
        contributors: contributors,
        linePaceCents: linePaceCents,
      ),
    );
  }

  @override
  ConsumerState<TrendPointContributorsSheet> createState() =>
      _TrendPointContributorsSheetState();
}

class _TrendPointContributorsSheetState()
    extends ConsumerState<TrendPointContributorsSheet> {
  /// Local category picks so rows update before the chart snapshot refreshes.
  final Map<String, String> _categoryOverrides = {};

  @override
  Widget build(BuildContext context) {
    return AppSheetPanel(
      heightFraction: 0.55,
      padForKeyboard: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: TrendPointContributorsSheet._contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(),
              if (widget.contributors.isEmpty)
                _emptyState()
              else
                _contributorList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader() {
    final linePaceLabel = _ContributorRow.formatPaceCents(widget.linePaceCents);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        ELayout.spaceLg,
        ELayout.spaceLg,
        ELayout.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top contributors', style: EText.section),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            '${widget.seriesName} · '
            '${DateFormat.yMMMd().format(widget.tapDate)} · '
            'line $linePaceLabel',
            style: EText.caption,
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Expanded(
      child: Center(
        child: Text(
          'No transactions in this window.',
          style: EText.body.medium,
        ),
      ),
    );
  }

  Widget _contributorList() {
    final categories =
        ref.watch(categoriesListProvider).asData?.value ??
        const <SpendCategory>[];
    final categoryById = {
      for (final category in categories) category.id: category,
    };
    final columnWidths = _ContributorColumnWidths.measure(
      contributors: widget.contributors,
      categoryNameFor: (contributor) =>
          _categoryFor(contributor, categoryById)?.name ?? 'Uncategorized',
    );

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ELayout.spaceLg,
              ELayout.spaceXs,
              ELayout.spaceLg,
              0,
            ),
            child: _ContributorHeaderRow(columnWidths: columnWidths),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                ELayout.spaceLg,
                0,
                ELayout.spaceLg,
                ELayout.spaceLg,
              ),
              itemCount: widget.contributors.length,
              itemBuilder: (context, index) {
                final contributor = widget.contributors[index];
                return _ContributorRow(
                  contributor: contributor,
                  rank: index + 1,
                  columnWidths: columnWidths,
                  showDivider: index < widget.contributors.length - 1,
                  category: _categoryFor(contributor, categoryById),
                  onCategorySelected: () => _changeCategory(contributor),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  SpendCategory? _categoryFor(
    TrendPointContributor contributor,
    Map<String, SpendCategory> categoryById,
  ) {
    final categoryId =
        _categoryOverrides[contributor.transaction.id] ??
        contributor.transaction.effectiveCategoryId;
    if (categoryId == null) return null;
    return categoryById[categoryId];
  }

  Future<void> _changeCategory(TrendPointContributor contributor) async {
    final categoryId = await RecategorizeSheet.show(
      context,
      ref: ref,
      transaction: contributor.transaction,
    );
    if (!mounted || categoryId == null) return;
    setState(() => _categoryOverrides[contributor.transaction.id] = categoryId);
  }
}

class const _ContributorColumnWidths({
  required final double rank,
  required final double date,
  required final double merchant,
  required final double pace,
  required final double amount,
  required final double category,
}) {
  static const paceHeader = 'Pace';
  static const amountHeader = 'Amount';

  static const _categoryChevronWidth = 12.0;
  static const _categoryChevronGap = 2.0;

  static _ContributorColumnWidths measure({
    required List<TrendPointContributor> contributors,
    required String Function(TrendPointContributor contributor) categoryNameFor,
  }) {
    final rankStyle = EText.body.medium.copyWith(
      fontWeight: FontWeight.w600,
      color: EColors.textMuted,
    );
    final dateStyle = EText.body.medium.copyWith(color: EColors.textMuted);
    final merchantStyle = EText.body.medium.copyWith(
      fontWeight: FontWeight.w600,
    );
    final paceStyle = EText.body.medium.copyWith(
      fontWeight: FontWeight.w600,
      color: EColors.textMuted,
    );
    final amountStyle = EText.body.medium.copyWith(fontWeight: FontWeight.w600);
    final categoryStyle = EText.caption.copyWith(
      fontWeight: FontWeight.w600,
      color: FinanceColors.accentPrimary,
    );
    final headerStyle = EText.caption;

    var rankWidth = 0.0;
    var dateWidth = 0.0;
    var merchantWidth = 0.0;
    var paceWidth = paceHeader.laidOutWidth(headerStyle);
    var amountWidth = amountHeader.laidOutWidth(headerStyle);
    var categoryWidth = 0.0;

    for (var index = 0; index < contributors.length; index++) {
      final contributor = contributors[index];
      final transaction = contributor.transaction;
      final merchantName = transaction.normalizedMerchant.trim().isNotEmpty
          ? transaction.normalizedMerchant
          : transaction.rawDescription;
      final paceLabel = _ContributorRow.formatPaceCents(
        contributor.smoothedContributionCents.round(),
      );
      final categoryLabel = categoryNameFor(contributor);

      rankWidth = _maxWidth(rankWidth, '${index + 1}', rankStyle);
      dateWidth = _maxWidth(
        dateWidth,
        DateFormat.yMMMd().format(transaction.postedAt),
        dateStyle,
      );
      merchantWidth = _maxWidth(merchantWidth, merchantName, merchantStyle);
      paceWidth = _maxWidth(paceWidth, paceLabel, paceStyle);
      amountWidth = _maxWidth(
        amountWidth,
        formatCents(transaction.amountCents),
        amountStyle,
      );
      categoryWidth = _maxWidth(categoryWidth, categoryLabel, categoryStyle);
    }

    return _ContributorColumnWidths(
      rank: rankWidth,
      date: dateWidth,
      merchant: merchantWidth,
      pace: paceWidth,
      amount: amountWidth,
      category: categoryWidth + _categoryChevronGap + _categoryChevronWidth,
    );
  }

  static double _maxWidth(double current, String text, TextStyle style) {
    final width = text.laidOutWidth(style);
    return width > current ? width : current;
  }
}

class const _ContributorHeaderRow({
  required final _ContributorColumnWidths columnWidths,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ELayout.spaceXs),
      child: Row(
        children: [
          AppSpreadsheetCell(width: columnWidths.rank, child: const SizedBox()),
          const SizedBox(width: ELayout.spaceSm),
          AppSpreadsheetCell(width: columnWidths.date, child: const SizedBox()),
          const SizedBox(width: ELayout.spaceSm),
          Flexible(
            fit: FlexFit.loose,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return AppSpreadsheetCell(
                  width: columnWidths.merchant.clamp(0.0, constraints.maxWidth),
                  child: const SizedBox(),
                );
              },
            ),
          ),
          const SizedBox(width: ELayout.spaceMd),
          AppSpreadsheetCell(
            width: columnWidths.pace,
            alignment: Alignment.centerRight,
            child: Text(
              _ContributorColumnWidths.paceHeader,
              style: EText.caption,
              maxLines: 1,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: ELayout.spaceMd),
          AppSpreadsheetCell(
            width: columnWidths.amount,
            alignment: Alignment.centerRight,
            child: Text(
              _ContributorColumnWidths.amountHeader,
              style: EText.caption,
              maxLines: 1,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: ELayout.spaceSm),
          AppSpreadsheetCell(
            width: columnWidths.category,
            child: const SizedBox(),
          ),
        ],
      ),
    );
  }
}

class const _ContributorRow({
  required final TrendPointContributor contributor,
  required final int rank,
  required final _ContributorColumnWidths columnWidths,
  required final bool showDivider,
  required final SpendCategory? category,
  required final VoidCallback onCategorySelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: ELayout.spaceSm),
      decoration: showDivider ? _rowDivider : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _rankLabel(),
          const SizedBox(width: ELayout.spaceSm),
          _postedDateLabel(),
          const SizedBox(width: ELayout.spaceSm),
          _merchantTitle(),
          const SizedBox(width: ELayout.spaceMd),
          _paceLabel(),
          const SizedBox(width: ELayout.spaceMd),
          _amountLabel(),
          const SizedBox(width: ELayout.spaceSm),
          _categoryPicker(),
        ],
      ),
    );
  }

  static const _rowDivider = BoxDecoration(
    border: Border(bottom: BorderSide(color: EColors.border, width: 0.5)),
  );

  Widget _rankLabel() {
    return AppSpreadsheetCell(
      width: columnWidths.rank,
      child: Text(
        '$rank',
        style: EText.body.medium.copyWith(
          fontWeight: FontWeight.w600,
          color: EColors.textMuted,
        ),
        maxLines: 1,
      ),
    );
  }

  Widget _postedDateLabel() {
    return AppSpreadsheetCell(
      width: columnWidths.date,
      child: Text(
        DateFormat.yMMMd().format(contributor.transaction.postedAt),
        style: EText.body.medium.copyWith(color: EColors.textMuted),
        maxLines: 1,
      ),
    );
  }

  Widget _merchantTitle() {
    return Flexible(
      fit: FlexFit.loose,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = columnWidths.merchant.clamp(0.0, constraints.maxWidth);
          return AppSpreadsheetCell(
            width: width,
            child: Text(
              _merchantName,
              style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }

  Widget _paceLabel() {
    return AppSpreadsheetCell(
      width: columnWidths.pace,
      alignment: Alignment.centerRight,
      child: Text(
        formatPaceCents(contributor.smoothedContributionCents.round()),
        style: EText.body.medium.copyWith(
          fontWeight: FontWeight.w600,
          color: EColors.textMuted,
        ),
        maxLines: 1,
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _amountLabel() {
    return AppSpreadsheetCell(
      width: columnWidths.amount,
      alignment: Alignment.centerRight,
      child: Text(
        formatCents(contributor.transaction.amountCents),
        style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
        maxLines: 1,
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _categoryPicker() {
    return AppSpreadsheetCell(
      width: columnWidths.category,
      child: InkWell(
        onTap: onCategorySelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category?.name ?? 'Uncategorized',
                style: EText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: FinanceColors.accentPrimary,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.expand_more,
                size: 12,
                color: FinanceColors.accentPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _merchantName {
    final transaction = contributor.transaction;
    if (transaction.normalizedMerchant.trim().isNotEmpty) {
      return transaction.normalizedMerchant;
    }
    return transaction.rawDescription;
  }

  /// Annualized pace label always in `/ yr` (full dollars, not compact `$3.4k`).
  static String formatPaceCents(int annualizedCents) {
    return '${formatCents(annualizedCents)}${TrendSpendRate.perYear.shortLabel}';
  }
}
