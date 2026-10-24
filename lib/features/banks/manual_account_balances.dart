import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_balance_snapshot.dart';
import 'package:spend_trends/domain/manual_accounts.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';

import 'manual_account_form_sheet.dart';

/// A manual account's update button and recorded balances, newest first.
class const ManualAccountBalances({
  required final Account account,
  required final List<AccountBalanceSnapshot> balanceSnapshots,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordedBalances = [
      for (final snapshot in balanceSnapshots.reversed)
        if (snapshot.accountId == account.id) snapshot,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPrimaryButton(
          onPressed: () =>
              ManualAccountFormSheet.show(context, account: account),
          child: const Text('Update balance'),
        ),
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Recorded balances',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        if (recordedBalances.isEmpty)
          Text('No balances recorded yet.', style: EText.caption)
        else
          for (final snapshot in recordedBalances)
            _recordedBalanceRow(context, ref, snapshot),
      ],
    );
  }

  Widget _recordedBalanceRow(
    BuildContext context,
    WidgetRef ref,
    AccountBalanceSnapshot snapshot,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            DateFormat.yMMMd().format(snapshot.recordedOn),
            style: EText.body.medium,
          ),
        ),
        Text(formatCents(snapshot.balanceCents), style: EText.body.medium),
        IconButton(
          tooltip: 'Remove this balance',
          visualDensity: VisualDensity.compact,
          onPressed: () => _deleteBalance(context, ref, snapshot),
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    );
  }

  Future<void> _deleteBalance(
    BuildContext context,
    WidgetRef ref,
    AccountBalanceSnapshot snapshot,
  ) async {
    final spendDataChanged = ref.read(spendDataChangedProvider.notifier);
    try {
      final ManualAccounts manualAccounts = await ref.read(
        manualAccountsProvider.future,
      );
      await manualAccounts.deleteBalance(snapshot);
      spendDataChanged.notify();
    } catch (error) {
      if (!context.mounted) return;
      context.textSnackBar('$error');
    }
  }
}
