import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/domain/trend_spend_rate.dart';

import 'bank_account_options.dart';

import 'package:spend_trends/features/trends/category_trend_chart.dart';
import 'package:spend_trends/features/trends/category_trend_series.dart';
import 'package:spend_trends/features/trends/net_worth_trend.dart';
import 'package:spend_trends/providers/spend_trends_providers.dart';

class const BankAccountDetailPane({required final Account account})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BankTransaction>> transactionsAsync = ref.watch(
      transactionsListProvider,
    );
    final AsyncValue<Map<String, Account>> accountsAsync = ref.watch(
      accountsMapProvider,
    );
    return ListView(
      padding: const EdgeInsets.all(ELayout.spaceLg).withOverlaidTabBar(context),
      children: [
        _accountSummary(),
        const SizedBox(height: ELayout.spaceLg),
        _balanceHistorySection(
          transactionsAsync: transactionsAsync,
          accountsAsync: accountsAsync,
        ),
      ],
    );
  }

  Widget _accountSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(account.displayName, style: EText.section),
        const SizedBox(height: ELayout.spaceXs),
        Text(account.institutionDisplayName, style: EText.body.medium),
        if (account.isCopilot) ...[
          const SizedBox(height: ELayout.spaceXs),
          Text('Copilot import', style: EText.caption),
        ],
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Balance',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceXs),
        Text(account.balanceCaption, style: EText.title),
        const SizedBox(height: ELayout.spaceLg),
        BankAccountOptions(account: account),
      ],
    );
  }

  Widget _balanceHistorySection({
    required AsyncValue<List<BankTransaction>> transactionsAsync,
    required AsyncValue<Map<String, Account>> accountsAsync,
  }) {
    if (transactionsAsync.hasError) {
      return Text(
        '${transactionsAsync.error}',
        style: EText.body.medium.copyWith(color: EColors.danger),
      );
    }
    if (accountsAsync.hasError) {
      return Text(
        '${accountsAsync.error}',
        style: EText.body.medium.copyWith(color: EColors.danger),
      );
    }
    final transactions = transactionsAsync.asData?.value;
    final accounts = accountsAsync.asData?.value;
    if (transactions == null || accounts == null) {
      return const SizedBox(
        height: 420,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return _balanceHistory(
      transactions: transactions,
      accounts: accounts.values.toList(),
    );
  }

  Widget _balanceHistory({
    required List<BankTransaction> transactions,
    required List<Account> accounts,
  }) {
    final CategoryTrendSeries? accountSeries =
        NetWorthTrend.balanceHistorySeries(
          account: account,
          accounts: accounts,
          transactions: transactions,
        );
    if (accountSeries == null || !accountSeries.canPlot) {
      return Text(
        'Not enough posted history to reconstruct a trend. '
        'The amount above is the current snapshot.',
        style: EText.caption,
      );
    }
    return CategoryTrendChart(
      title: 'Balance history',
      titleHelp:
          'Daily balance reconstructed from the current balance and posted '
          'transactions. Hover the chart to inspect a date.',
      subtitle: null,
      seriesList: [accountSeries],
      transactions: const <BankTransaction>[],
      categories: const <SpendCategory>[],
      groups: const <CategoryGroup>[],
      valueKind: TrendValueKind.level,
      enableContributors: false,
      chartHeight: 420,
    );
  }
}
