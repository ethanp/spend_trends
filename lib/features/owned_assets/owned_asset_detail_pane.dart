import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/features/owned_assets/owned_asset_form_sheet.dart';
import 'package:spend_trends/providers/spend_trends_providers.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

/// Owned-asset detail: current value, valuation history, edit / update / delete.
class const OwnedAssetDetailPane({required final String ownedAssetId})
    extends ConsumerWidget {
  static Future<void> showSheet(
    BuildContext context, {
    required String ownedAssetId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppSheetPanel(
        child: OwnedAssetDetailPane(ownedAssetId: ownedAssetId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownedAssets =
        ref.watch(ownedAssetsListProvider).asData?.value ?? const [];
    OwnedAssetWithValuations? ownedAsset;
    for (final candidate in ownedAssets) {
      if (candidate.asset.id == ownedAssetId) {
        ownedAsset = candidate;
        break;
      }
    }
    if (ownedAsset == null) {
      return const Padding(
        padding: EdgeInsets.all(ELayout.spaceLg),
        child: Text('Owned asset removed.'),
      );
    }
    return _detailList(context, ref, ownedAsset);
  }

  Widget _detailList(
    BuildContext context,
    WidgetRef ref,
    OwnedAssetWithValuations ownedAsset,
  ) {
    return ListView(
      padding: const EdgeInsets.all(ELayout.spaceLg).withOverlaidTabBar(context),
      children: [
        Text(ownedAsset.asset.name, style: EText.section),
        const SizedBox(height: ELayout.spaceXs),
        Text(ownedAsset.asset.kind.legendLabel, style: EText.caption),
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Value',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceXs),
        Text(formatCents(ownedAsset.currentValueCents), style: EText.title),
        if (ownedAsset.currentValuedOn != null) ...[
          const SizedBox(height: ELayout.spaceXs),
          Text(
            'Valued ${DateFormat.yMMMd().format(ownedAsset.currentValuedOn!)}',
            style: EText.caption,
          ),
        ],
        if (ownedAsset.asset.note != null) ...[
          const SizedBox(height: ELayout.spaceMd),
          Text(ownedAsset.asset.note!, style: EText.body.medium),
        ],
        const SizedBox(height: ELayout.spaceLg),
        ..._actions(context, ownedAsset),
        const SizedBox(height: ELayout.spaceLg),
        ..._valuationHistory(context, ref, ownedAsset),
        const SizedBox(height: ELayout.spaceLg),
        TextButton(
          onPressed: () => _confirmDelete(context, ref, ownedAsset),
          style: TextButton.styleFrom(foregroundColor: EColors.danger),
          child: const Text('Delete owned asset'),
        ),
      ],
    );
  }

  List<Widget> _actions(
    BuildContext context,
    OwnedAssetWithValuations ownedAsset,
  ) {
    return [
      AppPrimaryButton(
        onPressed: () => OwnedAssetFormSheet.show(
          context,
          ownedAsset: ownedAsset,
          updateValueOnly: true,
        ),
        child: const Text('Update value'),
      ),
      const SizedBox(height: ELayout.spaceSm),
      TextButton(
        onPressed: () =>
            OwnedAssetFormSheet.show(context, ownedAsset: ownedAsset),
        child: const Text('Edit'),
      ),
    ];
  }

  List<Widget> _valuationHistory(
    BuildContext context,
    WidgetRef ref,
    OwnedAssetWithValuations ownedAsset,
  ) {
    final valuations = ownedAsset.valuations;
    return [
      Text(
        'Valuation history',
        style: EText.caption.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: ELayout.spaceSm),
      if (valuations.isEmpty)
        Text('No valuations yet.', style: EText.caption)
      else
        for (final valuation in valuations)
          _valuationRow(
            context,
            ref,
            valuation,
            canDelete: valuations.length > 1,
          ),
    ];
  }

  Widget _valuationRow(
    BuildContext context,
    WidgetRef ref,
    OwnedAssetValuation valuation, {
    required bool canDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ELayout.spaceSm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateFormat.yMMMd().format(valuation.valuedOn),
              style: EText.body.medium,
            ),
          ),
          Text(formatCents(valuation.valueCents), style: EText.body.medium),
          if (canDelete)
            IconButton(
              tooltip: 'Remove this valuation',
              onPressed: () => _deleteValuation(context, ref, valuation),
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteValuation(
    BuildContext context,
    WidgetRef ref,
    OwnedAssetValuation valuation,
  ) async {
    try {
      final repository = await ref.read(ownedAssetsRepositoryProvider.future);
      await repository.deleteValuation(valuation.id);
      ref.read(spendDataChangedProvider.notifier).notify();
    } catch (error) {
      if (!context.mounted) return;
      context.textSnackBar('$error');
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    OwnedAssetWithValuations ownedAsset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete owned asset?'),
        content: Text('“${ownedAsset.asset.name}” will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: EColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repository = await ref.read(ownedAssetsRepositoryProvider.future);
    await repository.deleteAsset(ownedAsset.asset.id);
    ref.read(spendDataChangedProvider.notifier).notify();
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
