import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/remove_copilot_duplicates.dart';
import 'package:spend_trends/features/settings/settings_section.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';

import 'remove_copilot_duplicates_provider.dart';

/// Removes duplicate transactions from Copilot re-imports and linked SimpleFIN.
class const RemoveDuplicateTransactionsTile() extends ConsumerStatefulWidget {
  @override
  ConsumerState<RemoveDuplicateTransactionsTile> createState() =>
      _RemoveDuplicateTransactionsTileState();
}

class _RemoveDuplicateTransactionsTileState()
    extends ConsumerState<RemoveDuplicateTransactionsTile> {
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return SettingsToolRow(
      icon: Icons.layers,
      title: 'Remove duplicate transactions',
      caption:
          'Drop Copilot↔SimpleFIN matches and same-account day/amount/merchant '
          'duplicates.',
      onActivated: _run,
      style: SettingsSectionStyle.maintenance,
      busy: _busy,
      message: _message,
    );
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final remover = await ref.read(removeCopilotDuplicatesProvider.future);
      final result = await remover.run();
      ref.read(spendDataChangedProvider.notifier).notify();
      setState(() => _message = _resultMessage(result));
    } catch (error) {
      setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _resultMessage(RemoveCopilotDuplicatesResult result) {
    final parts = <String>[];
    if (result.deletedCopilotCount > 0) {
      parts.add(
        'Removed ${result.deletedCopilotCount} Copilot↔SimpleFIN duplicates',
      );
    }
    if (result.deletedSameAccountCount > 0) {
      parts.add(
        'removed ${result.deletedSameAccountCount} same-account duplicates',
      );
    }
    if (result.categoriesCopiedToSimplefin > 0) {
      parts.add('copied ${result.categoriesCopiedToSimplefin} categories');
    }
    if (parts.isEmpty) {
      if (result.linkedAccountMasks == 0) {
        return 'No linked accounts and no same-account duplicates found.';
      }
      return 'No duplicates found across ${result.linkedAccountMasks} linked '
          'accounts.';
    }
    return '${parts.join('; ')}.';
  }
}
