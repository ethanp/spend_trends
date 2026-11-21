import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/ui/banks/bank_name_rename_field.dart';

class const BankInstitutionHeader({
  required final Account sampleAccount,
  required final String displayName,
  required final Color accentColor,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleStyle = EText.body.large.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: -0.2,
      color: accentColor,
    );
    if (sampleAccount.isCopilot) return Text(displayName, style: titleStyle);
    return BankNameRenameField(
      displayName: displayName,
      hintText: sampleAccount.connName?.trim().isNotEmpty == true
          ? sampleAccount.connName!
          : 'Bank name',
      nameStyle: titleStyle,
      accentColor: accentColor,
      onRenameConfirmed: (typedName) => _renameInstitution(ref, typedName),
    );
  }

  Future<void> _renameInstitution(WidgetRef ref, String typedName) async {
    final unchanged =
        typedName == displayName ||
        (typedName.isEmpty &&
            sampleAccount.connUserLabel.trimmedOrEmpty.isEmpty);
    if (unchanged) return;
    final repository = await ref.read(accountsRepositoryProvider.future);
    await repository.updateInstitutionUserLabel(
      account: sampleAccount,
      connUserLabel:
          typedName.isEmpty ||
              typedName == sampleAccount.connName.trimmedOrEmpty
          ? null
          : typedName,
    );
    ref.read(spendDataChangedProvider.notifier).notify();
  }
}
