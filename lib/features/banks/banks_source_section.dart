import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/features/banks/bank_accounts_list.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_section.dart';
import 'package:spend_trends/features/banks/banks_controller.dart';
import 'package:spend_trends/features/banks/banks_pull_live_session.dart';
import 'package:spend_trends/services/simplefin/simplefin_access_store.dart';
import 'package:spend_trends/theme/finance_colors.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/help_tooltip.dart';

import 'connection_status.dart';

/// Everyday bank UI: connect, accounts, pull bank transactions.
class const BanksSourceSection({
  final String? selectedAccountId,
  final void Function(String accountId)? onAccountSelected,
  final String? selectedOwnedAssetId,
  final void Function(String ownedAssetId)? onOwnedAssetSelected,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<BanksSourceSection> createState() => _BanksSourceSectionState();
}

class _BanksSourceSectionState() extends ConsumerState<BanksSourceSection> {
  final TextEditingController _tokenController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionAsync = ref.watch(connectionStatusProvider);
    final actionState = ref.watch(banksControllerProvider);

    return connectionAsync.when(
      skipLoadingOnReload: true,
      loading: () => const CircularProgressIndicator(),
      error: (error, _) => SelectableText(
        '$error',
        style: EText.body.medium.copyWith(color: EColors.danger),
      ),
      data: (status) {
        if (!status.isConnected) return _disconnectedBody(actionState);
        return _connectedBody(status, actionState);
      },
    );
  }

  Widget _disconnectedBody(BanksActionState actionState) {
    final busy = actionState.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paste a Setup Token from SimpleFIN, or set '
          '${SimpleFinAccessStore.envAccessUrlKey} in .env.',
          style: EText.caption,
        ),
        const SizedBox(height: ELayout.spaceMd),
        AppPrimaryButton(
          busy: busy,
          onPressed: () =>
              ref.read(banksControllerProvider.notifier).openSimpleFin(),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: ELayout.spaceSm),
              Text('Open SimpleFIN'),
            ],
          ),
        ),
        const SizedBox(height: ELayout.spaceMd),
        TextField(
          controller: _tokenController,
          maxLines: 4,
          minLines: 3,
          style: EText.body.medium.copyWith(color: EColors.textPrimary),
          decoration: EInput.filled(
            hintText: 'Paste Setup Token',
            hintStyle: EText.body.medium.copyWith(color: EColors.textMuted),
            fillColor: EColors.surfaceInset,
            focusedBorder: EInput.outlineSm.copyWith(
              borderSide: const BorderSide(color: FinanceColors.accentPrimary),
            ),
          ),
        ),
        if (actionState.actionError != null) ...[
          const SizedBox(height: ELayout.spaceSm),
          SelectableText(
            actionState.actionError!,
            style: EText.caption.copyWith(color: EColors.danger),
          ),
        ],
        const SizedBox(height: ELayout.spaceMd),
        AppPrimaryButton(
          busy: busy,
          onPressed: _connect,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 18),
              SizedBox(width: ELayout.spaceSm),
              Text('Connect'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _connectedBody(ConnectionStatus status, BanksActionState actionState) {
    final busy = actionState.busy;
    final controller = ref.read(banksControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BankAccountsList(
          status: status,
          actionError: actionState.actionError,
          selectedAccountId: widget.selectedAccountId,
          onAccountSelected: widget.onAccountSelected,
        ),
        const SizedBox(height: ELayout.spaceXl),
        OwnedAssetsSection(
          selectedOwnedAssetId: widget.selectedOwnedAssetId,
          onOwnedAssetSelected: widget.onOwnedAssetSelected,
        ),
        const SizedBox(height: ELayout.spaceMd),
        Row(
          children: [
            AppPrimaryButton(
              busy: busy,
              onPressed: () => ref
                  .read(banksPullLiveSessionProvider.notifier)
                  .runPull(
                    (onProgress) =>
                        controller.syncLatest(onProgress: onProgress),
                  ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync, size: 18),
                  SizedBox(width: ELayout.spaceSm),
                  Text('Pull bank transactions'),
                ],
              ),
            ),
            const SizedBox(width: ELayout.spaceSm),
            const HelpTooltip(
              message:
                  'Since the last SimpleFIN update. Window starts 2 days '
                  'before that pull so late posts aren\'t missed. '
                  'Already-saved rows are updated, not duplicated.',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _connect() async {
    final controller = ref.read(banksControllerProvider.notifier);
    final accessUrl = await controller.connect(_tokenController.text);
    if (ref.read(banksControllerProvider).actionError != null) return;
    _tokenController.clear();
    if (accessUrl != null && mounted) {
      await promptPersistAccessUrl(context, accessUrl);
    }
  }
}
