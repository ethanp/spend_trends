import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';
import 'package:spend_trends/widgets/help_tooltip.dart';

import 'banks_providers.dart';

/// Kind and prior-account editors for the Banks account detail pane.
class const BankAccountOptions({required final Account account})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<BankAccountOptions> createState() => _BankAccountOptionsState();
}

class _BankAccountOptionsState() extends ConsumerState<BankAccountOptions> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _optionPicker(
          label: 'Account type',
          value: widget.account.kind.legendLabel,
          onActivated: _saving ? null : () => _pickKind(context),
        ),
        const SizedBox(height: ELayout.spaceLg),
        _optionPicker(
          label: 'Prior account of',
          helpMessage:
              'Use when a loan or bank account moved servicers. '
              'This balance drops out of net worth; its transactions stay in '
              'the current account\'s history.',
          value: _priorAccountCaption(),
          onActivated: _saving ? null : () => _pickPriorAccount(context),
        ),
      ],
    );
  }

  Widget _optionPicker({
    required String label,
    required String value,
    required VoidCallback? onActivated,
    String? helpMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: EText.caption.copyWith(fontWeight: FontWeight.w600),
            ),
            if (helpMessage != null) ...[
              const SizedBox(width: ELayout.spaceXs),
              HelpTooltip(message: helpMessage),
            ],
          ],
        ),
        const SizedBox(height: ELayout.spaceXs),
        GestureDetector(
          onTap: onActivated,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  value,
                  style: EText.body.medium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: ELayout.spaceXs),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: EColors.textMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _priorAccountCaption() {
    final parentId = widget.account.belongsToAccountId;
    if (parentId == null) return 'None';
    final accounts = ref.watch(accountsMapProvider).asData?.value;
    return accounts?[parentId]?.displayNameWithInstitution ?? 'Unknown';
  }

  Future<void> _pickKind(BuildContext context) async {
    final selected = await showModalBottomSheet<AccountKind>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppSheetPanel.compact(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ELayout.spaceLg,
                ELayout.spaceLg,
                ELayout.spaceLg,
                ELayout.spaceSm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Account type', style: EText.section),
              ),
            ),
            for (final kind in AccountKind.values)
              ListTile(
                title: Text(
                  kind.legendLabel,
                  style: kind == widget.account.kind
                      ? EText.body.medium.copyWith(fontWeight: FontWeight.w600)
                      : EText.body.medium,
                ),
                onTap: () => Navigator.of(sheetContext).pop(kind),
              ),
            ListTile(
              title: Text(
                'Cancel',
                style: EText.body.medium.copyWith(color: EColors.textMuted),
              ),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: ELayout.spaceMd),
          ],
        ),
      ),
    );
    if (selected == null || selected == widget.account.kind || !mounted) {
      return;
    }

    setState(() => _saving = true);
    try {
      final repository = await ref.read(accountsRepositoryProvider.future);
      await repository.updateKind(accountId: widget.account.id, kind: selected);
      ref.read(spendDataChangedProvider.notifier).notify();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPriorAccount(BuildContext context) async {
    final Map<String, Account>? accounts = ref
        .read(accountsMapProvider)
        .asData
        ?.value;
    if (accounts == null) return;

    final parents =
        [
          for (final account in accounts.values)
            if (account.id != widget.account.id &&
                !account.isCopilot &&
                !account.hasParent)
              account,
        ]..sort(
          (left, right) => left.displayName.toLowerCase().compareTo(
            right.displayName.toLowerCase(),
          ),
        );

    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppSheetPanel.compact(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ELayout.spaceLg,
                ELayout.spaceLg,
                ELayout.spaceLg,
                ELayout.spaceSm,
              ),
              child: Text('Prior account of', style: EText.section),
            ),
            ListTile(
              title: Text(
                'None',
                style: widget.account.belongsToAccountId == null
                    ? EText.body.medium.copyWith(fontWeight: FontWeight.w600)
                    : EText.body.medium,
              ),
              onTap: () => Navigator.of(sheetContext).pop(''),
            ),
            for (final parent in parents)
              ListTile(
                title: Text(
                  parent.displayNameWithInstitution,
                  style: parent.id == widget.account.belongsToAccountId
                      ? EText.body.medium.copyWith(fontWeight: FontWeight.w600)
                      : EText.body.medium,
                ),
                onTap: () => Navigator.of(sheetContext).pop(parent.id),
              ),
            ListTile(
              title: Text(
                'Cancel',
                style: EText.body.medium.copyWith(color: EColors.textMuted),
              ),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: ELayout.spaceMd),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    final nextParentId = selected.isEmpty ? null : selected;
    if (nextParentId == widget.account.belongsToAccountId) return;

    setState(() => _saving = true);
    try {
      final repository = await ref.read(accountsRepositoryProvider.future);
      await repository.updateBelongsTo(
        accountId: widget.account.id,
        belongsToAccountId: nextParentId,
      );
      ref.read(spendDataChangedProvider.notifier).notify();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
