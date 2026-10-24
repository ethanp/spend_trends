import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';

/// Shared column widths for Activity list rows so cells align.
///
/// [measure] captures natural (no-ellipsis) widths. [allocate] shrinks those
/// into a concrete pane width when the window is too narrow to fit everything.
class const ActivityColumnWidths({
  required final double category,
  required final double account,
  required final double title,
  required final double amount,
}) {
  static const titleFloor = 200.0;
  static const _categoryColorBarWidth = 5.0;
  static const _surfaceBorder = 2.0;
  static const _scrollbarGutter = 16.0;
  static const _fitSlack = 32.0;
  static const _ruleTrailing = 72.0;
  static const _listHorizontalPad = ELayout.spaceLg * 2;
  static const _rowHorizontalPad = ELayout.spaceMd * 2;
  static const _gaps = ELayout.spaceSm * 2 + ELayout.spaceMd;

  /// Inflate painted widths slightly — fallback fonts and subpixel rounding
  /// otherwise make [contentFitWidth] stop short while cells still ellipsize.
  static const _fallbackFontWidthInflation = 1.12;

  static double get _colorBarAndInsetsWidth =>
      _categoryColorBarWidth +
      _surfaceBorder +
      _scrollbarGutter +
      _fitSlack +
      _listHorizontalPad +
      _rowHorizontalPad +
      _ruleTrailing +
      _gaps;

  /// Pane width that shows every measured cell without ellipsis.
  double get contentFitWidth =>
      _colorBarAndInsetsWidth + category + account + title + amount;

  static ActivityColumnWidths measure({
    required List<BankTransaction> transactions,
    required Map<String, Account> accounts,
    required Map<String, SpendCategory> categories,
  }) {
    final categoryStyle = EText.caption.copyWith(fontWeight: FontWeight.w600);
    final accountStyle = EText.caption;
    final titleStyle = EText.body.medium.copyWith(fontWeight: FontWeight.w600);
    final amountStyle = EText.body.medium.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    var categoryWidth = 'Uncategorized'.laidOutWidth(categoryStyle);
    var accountWidth = 0.0;
    var titleWidth = titleFloor;
    var amountWidth = formatCents(0).laidOutWidth(amountStyle);

    for (final transaction in transactions) {
      final categoryName =
          categories[transaction.categoryId]?.name ?? 'Uncategorized';
      final categoryPaint = categoryName.laidOutWidth(categoryStyle);
      if (categoryPaint > categoryWidth) categoryWidth = categoryPaint;

      final account = accounts[transaction.accountId];
      if (account != null) {
        final accountPaint = account.displayNameWithInstitution.laidOutWidth(
          accountStyle,
        );
        if (accountPaint > accountWidth) accountWidth = accountPaint;
      }

      final merchantName = transaction.rawDescription.isEmpty
          ? transaction.normalizedMerchant
          : transaction.rawDescription;
      final titlePaint = merchantName.laidOutWidth(titleStyle);
      if (titlePaint > titleWidth) titleWidth = titlePaint;

      final amountPaint = formatCents(transaction.amountCents)
          .laidOutWidth(amountStyle);
      if (amountPaint > amountWidth) amountWidth = amountPaint;
    }

    return ActivityColumnWidths(
      category: categoryWidth * _fallbackFontWidthInflation,
      account: accountWidth * _fallbackFontWidthInflation,
      title: math.max(titleFloor, titleWidth * _fallbackFontWidthInflation),
      amount: amountWidth * _fallbackFontWidthInflation,
    );
  }

  /// Column sizes for a concrete list pane width. Prefers natural widths;
  /// shrinks title first, then category/account together, when space is short.
  ActivityColumnWidths allocate(double listPaneWidth) {
    final inner = math.max(0.0, listPaneWidth - _colorBarAndInsetsWidth);
    final afterAmount = math.max(0.0, inner - amount);
    final naturalFlexible = category + account + title;

    if (naturalFlexible <= afterAmount) {
      return ActivityColumnWidths(
        category: category,
        account: account,
        title: title,
        amount: amount,
      );
    }

    final categoryAccount = category + account;
    if (categoryAccount + titleFloor <= afterAmount) {
      return ActivityColumnWidths(
        category: category,
        account: account,
        title: afterAmount - categoryAccount,
        amount: amount,
      );
    }

    final flexibleBudget = math.max(0.0, afterAmount - titleFloor);
    if (categoryAccount <= 0) {
      return ActivityColumnWidths(
        category: 0,
        account: 0,
        title: afterAmount,
        amount: amount,
      );
    }

    final scale = flexibleBudget / categoryAccount;
    return ActivityColumnWidths(
      category: category * scale,
      account: account * scale,
      title: titleFloor,
      amount: amount,
    );
  }
}
