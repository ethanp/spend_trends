import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/ui/banks/bank_name_rename_field.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';

class const BankAccountBalanceRow({
  required final Account account,
  required final double amountColumnWidth,
  final bool selected = false,
  final VoidCallback? onActivated,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decorated = selected
        ? ESurface(
            kind: ESurfaceKind.tinted,
            accent: FinanceColors.accentPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: ELayout.spaceSm,
              vertical: ELayout.spaceXs,
            ),
            borderRadius: ELayout.borderRadiusSm,
            child: _rowBody(ref),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ELayout.spaceSm,
              vertical: ELayout.spaceXs,
            ),
            child: _rowBody(ref),
          );

    if (onActivated == null) return decorated;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onActivated,
      child: decorated,
    );
  }

  Widget _rowBody(WidgetRef ref) {
    final exceptionLabel = _exceptionLabel(account);
    final nameAndBalance = _nameAndBalance(
      ref,
      emphasizeName: exceptionLabel != null,
    );
    if (exceptionLabel == null) return nameAndBalance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nameAndBalance,
        Text(
          exceptionLabel,
          style: EText.caption.copyWith(color: EColors.warning),
        ),
      ],
    );
  }

  Widget _nameAndBalance(WidgetRef ref, {required bool emphasizeName}) {
    final isMutedBalance =
        !account.countsTowardNetWorth || account.balanceCents == 0;
    final nameStyle = emphasizeName
        ? EText.body.medium.copyWith(fontWeight: FontWeight.w600)
        : EText.body.medium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _accountName(ref, nameStyle)),
        const SizedBox(width: ELayout.spaceMd),
        SizedBox(
          width: amountColumnWidth,
          child: Text(
            account.balanceCaption,
            style: isMutedBalance
                ? EText.body.medium.copyWith(color: EColors.textMuted)
                : EText.body.medium.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _accountName(WidgetRef ref, TextStyle nameStyle) {
    return BankNameRenameField(
      displayName: account.displayName,
      hintText: account.name,
      nameStyle: nameStyle,
      accentColor: FinanceColors.accentPrimary,
      onRenameConfirmed: (typedName) => _renameAccount(ref, typedName),
    );
  }

  Future<void> _renameAccount(WidgetRef ref, String typedName) async {
    final unchanged =
        typedName == account.displayName ||
        (typedName.isEmpty && account.userLabel.trimmedOrEmpty.isEmpty);
    if (unchanged) return;
    final repository = await ref.read(accountsRepositoryProvider.future);
    // Empty field clears custom label back to the official bank name.
    await repository.updateUserLabel(
      accountId: account.id,
      userLabel: typedName.isEmpty || typedName == account.name
          ? null
          : typedName,
    );
    ref.read(spendDataChangedProvider.notifier).notify();
  }

  static String? _exceptionLabel(Account account) {
    return switch (account.status) {
      AccountStatus.ok when account.isManualBalanceStale(DateTime.now()) =>
        account.balanceAsOf == null
            ? 'No balance recorded'
            : 'Balance as of ${DateFormat.yMMMd().format(account.balanceAsOf!)}',
      AccountStatus.ok => null,
      AccountStatus.needsRelink => 'Needs re-link',
      AccountStatus.stale => 'Stale',
      AccountStatus.error =>
        account.statusMessage?.trim().isNotEmpty == true
            ? account.statusMessage
            : 'Error',
    };
  }
}
