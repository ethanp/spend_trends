import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/features/banks/bank_pull_history_sheet.dart';
import 'package:spend_trends/features/banks/banks_controller.dart';
import 'package:spend_trends/features/banks/banks_pull_live_session.dart';
import 'package:spend_trends/features/settings/settings_section.dart';
import 'package:spend_trends/services/simplefin/simplefin_access_store.dart';

import 'connection_status.dart';

/// Settings-only bank maintenance: full history re-fetch and disconnect.
class const BanksAdvancedSection() extends ConsumerWidget {
  static const _style = SettingsSectionStyle.banks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(connectionStatusProvider);
    final actionState = ref.watch(banksControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          icon: Icons.apartment,
          title: 'Banks',
          style: _style,
        ),
        const SizedBox(height: ELayout.spaceMd),
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
    if (!status.isConnected) {
      return const Text(
        'Connect a bank on the Banks tab to sync accounts and transactions.',
        style: SettingsType.sectionMeta,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_connectedCaption(status), style: SettingsType.sectionMeta),
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
        const SizedBox(height: ELayout.spaceLg),
        SettingsToolRow(
          icon: Icons.add_circle,
          title: 'Add account',
          caption: 'Opens SimpleFIN Bridge to link another institution.',
          onActivated: () =>
              ref.read(banksControllerProvider.notifier).openSimpleFinBridge(),
          style: _style,
          busy: actionState.busy,
        ),
        const SizedBox(height: ELayout.spaceLg),
        SettingsToolRow(
          icon: Icons.history,
          title: 'Pull history',
          caption:
              'Recent SimpleFIN pulls, including per-account outages and '
              'bridge warnings.',
          onActivated: () => BankPullHistorySheet.show(context),
          style: _style,
          busy: actionState.busy,
        ),
        const SizedBox(height: ELayout.spaceLg),
        SettingsToolRow(
          icon: Icons.cloud_download,
          title: 'Re-download all history',
          caption:
              'Fetches ~2 years from SimpleFIN again. Everyday "Pull bank '
              'transactions" only covers since the last SimpleFIN update '
              '(window starts 2 days earlier).',
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
        const SizedBox(height: ELayout.spaceLg),
        SettingsToolRow(
          icon: Icons.delete,
          title: 'Disconnect & erase',
          caption: 'Removes the connection and local accounts/transactions.',
          onActivated: () => _disconnect(context, ref),
          style: _style,
          busy: actionState.busy,
        ),
      ],
    );
  }

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
