import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/ui/banks/bank_pull_history_sheet.dart';
import 'package:spend_trends/ui/banks/banks_controller.dart';
import 'package:spend_trends/ui/banks/banks_pull_live_session.dart';
import 'package:spend_trends/ui/settings/csv_import_sheet.dart';
import 'package:spend_trends/ui/settings/settings_action_row.dart';
import 'package:spend_trends/data/simplefin/simplefin_access_store.dart';

import 'connection_status.dart';

/// Settings for bank connections: add, history, re-download, disconnect, and
/// manual CSV import.
class const BanksAdvancedSection() extends ConsumerWidget {
  static const _style = SettingsSectionStyle.banks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(connectionStatusProvider);
    final actionState = ref.watch(banksControllerProvider);

    return ESettingsSection(
      title: 'Banks',
      children: [
        connectionAsync.when(
          skipLoadingOnReload: true,
          loading: () => const CircularProgressIndicator(),
          error: (error, _) => SelectableText(
            '$error',
            style: EText.body.medium.copyWith(color: EColors.danger),
          ),
          data: (status) => _body(context, ref, status, actionState),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    ConnectionStatus status,
    BanksActionState actionState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          status.isConnected
              ? _connectedCaption(status)
              : 'Connect a bank on the Banks tab to sync accounts and '
                    'transactions.',
          style: SettingsType.sectionMeta,
        ),
        if (status.fromEnv) ...[
          const SizedBox(height: ELayout.spaceSm),
          const Text(
            'Access URL comes from '
            '${SimpleFinAccessStore.envAccessUrlKey} in .env. '
            'Remove that line and restart to disconnect.',
            style: SettingsType.sectionMeta,
          ),
        ],
        if (actionState.actionError != null) ...[
          const SizedBox(height: ELayout.spaceSm),
          SelectableText(
            actionState.actionError!,
            style: EText.caption.copyWith(color: EColors.danger),
          ),
        ],
        const SizedBox(height: ELayout.spaceMd),
        ESettingsRowGroup(
          children: [
            if (status.isConnected)
              ..._connectedBankRows(context, ref, actionState),
            SettingsActionRow(
              icon: Icons.description,
              title: 'Import CSV',
              caption: "Manual import when a bank won't sync",
              onActivated: () => CsvImportSheet.show(context),
              style: _style,
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _connectedBankRows(
    BuildContext context,
    WidgetRef ref,
    BanksActionState actionState,
  ) => [
    SettingsActionRow(
      icon: Icons.add_circle,
      title: 'Add account',
      caption: 'Link another bank through SimpleFIN',
      onActivated: () =>
          ref.read(banksControllerProvider.notifier).openSimpleFinBridge(),
      style: _style,
      busy: actionState.busy,
    ),
    SettingsActionRow(
      icon: Icons.history,
      title: 'Pull history',
      caption: 'Past pulls, outages, and warnings',
      onActivated: () => BankPullHistorySheet.show(context),
      style: _style,
      busy: actionState.busy,
    ),
    SettingsActionRow(
      icon: Icons.cloud_download,
      title: 'Re-download all history',
      caption: 'Fetch the last ~2 years again',
      onActivated: () => ref
          .read(banksPullLiveSessionProvider.notifier)
          .runPull(
            (onProgress) => ref
                .read(banksControllerProvider.notifier)
                .refreshFullHistory(onProgress: onProgress),
          ),
      style: _style,
      busy: actionState.busy,
    ),
    SettingsActionRow(
      icon: Icons.delete,
      title: 'Disconnect & erase',
      caption: 'Unlink and delete local bank data',
      onActivated: () => _disconnect(context, ref),
      style: _style,
      busy: actionState.busy,
    ),
  ];

  String _connectedCaption(ConnectionStatus status) {
    final source = status.fromEnv ? 'SimpleFIN (.env)' : 'SimpleFIN';
    final accountCount = status.accounts.length;
    final accountLabel =
        '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}';
    return '$source · $accountLabel · manage everyday sync on the Banks tab';
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDisconnectAndErase(context);
    if (!confirmed || !context.mounted) return;
    await ref
        .read(banksControllerProvider.notifier)
        .disconnect(confirmed: true);
  }
}
