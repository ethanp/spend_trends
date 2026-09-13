import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/features/owned_assets/owned_asset_detail_pane.dart';
import 'package:spend_trends/features/owned_assets/owned_asset_form_sheet.dart';
import 'package:spend_trends/features/owned_assets/owned_asset_row.dart';
import 'package:spend_trends/widgets/app_browse_split_shell.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/help_tooltip.dart';

import 'owned_assets_providers.dart';

/// Banks section: manually tracked home / vehicle / other asset values.
class const OwnedAssetsSection({
  final String? selectedOwnedAssetId,
  final void Function(String ownedAssetId)? onOwnedAssetSelected,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownedAssetsAsync = ref.watch(ownedAssetsListProvider);
    return ownedAssetsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: ELayout.spaceMd),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(
        '$error',
        style: EText.body.medium.copyWith(color: EColors.danger),
      ),
      data: (ownedAssets) => _section(context, ownedAssets),
    );
  }

  Widget _section(
    BuildContext context,
    List<OwnedAssetWithValuations> ownedAssets,
  ) {
    final amountColumnWidth = _amountColumnWidth(ownedAssets);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Owned assets', style: EText.section),
            const SizedBox(width: ELayout.spaceXs),
            const HelpTooltip(
              message:
                  'Home, vehicle, and other values in net worth. '
                  'Update a value to record a snapshot on that date.',
            ),
          ],
        ),
        const SizedBox(height: ELayout.spaceMd),
        if (ownedAssets.isEmpty)
          Text('No owned assets yet.', style: EText.caption)
        else
          for (final ownedAsset in ownedAssets)
            OwnedAssetRow(
              ownedAsset: ownedAsset,
              amountColumnWidth: amountColumnWidth,
              selected: ownedAsset.asset.id == selectedOwnedAssetId,
              onActivated: () => _selectOrShowDetail(context, ownedAsset),
            ),
        const SizedBox(height: ELayout.spaceMd),
        AppPrimaryButton(
          onPressed: () => OwnedAssetFormSheet.show(context),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: ELayout.spaceSm),
              Text('Add owned asset'),
            ],
          ),
        ),
      ],
    );
  }

  void _selectOrShowDetail(
    BuildContext context,
    OwnedAssetWithValuations ownedAsset,
  ) {
    if (AppBrowseSplitShell.isSplit(context) && onOwnedAssetSelected != null) {
      onOwnedAssetSelected!(ownedAsset.asset.id);
      return;
    }
    OwnedAssetDetailPane.showSheet(context, ownedAssetId: ownedAsset.asset.id);
  }

  static double _amountColumnWidth(List<OwnedAssetWithValuations> ownedAssets) {
    var widest = 0.0;
    for (final ownedAsset in ownedAssets) {
      final amountStyle = ownedAsset.currentValueCents == 0
          ? EText.body.medium.copyWith(color: EColors.textMuted)
          : EText.body.medium.copyWith(fontWeight: FontWeight.w600);
      final width = formatCents(ownedAsset.currentValueCents)
          .laidOutWidth(amountStyle);
      if (width > widest) widest = width;
    }
    return widest;
  }
}
