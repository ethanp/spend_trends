import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

class const CategoryEditorRetireSection({required final VoidCallback? onMergeStarted})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Retire',
          style: EText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceXs),
        Text(
          'Merge this category into another. Transactions and rules move '
          'to the survivor, then this category is removed.',
          style: EText.caption,
        ),
        const SizedBox(height: ELayout.spaceSm),
        TextButton(
          onPressed: onMergeStarted,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: EColors.danger,
          ),
          child: const Text('Merge into…'),
        ),
      ],
    );
  }
}

class const CategoryMergeTargetPicker({
  required final SpendCategory category,
  required final List<SpendCategory> mergeTargets,
  required final ValueChanged<SpendCategory> onTargetSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppSheetPanel(
      heightFraction: 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(ELayout.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Retire ${category.name} into…', style: EText.section),
                const SizedBox(height: ELayout.spaceXs),
                Text(
                  'Retire ${category.name} into the survivor · moves transactions '
                  'and rules, then removes ${category.name}.',
                  style: EText.caption,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: mergeTargets.length,
              itemBuilder: (context, index) {
                final target = mergeTargets[index];
                return ListTile(
                  title: Text(target.name, style: EText.section),
                  onTap: () => onTargetSelected(target),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryMergeConfirmation() {
  static Future<bool?> show({
    required BuildContext context,
    required SpendCategory category,
    required SpendCategory target,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Retire ${category.name} into ${target.name}?'),
          content: Text(
            'Retire ${category.name} into ${target.name} · moves transactions '
            'and rules. ${category.name} is then deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: EColors.danger),
              child: const Text('Merge & delete'),
            ),
          ],
        );
      },
    );
  }
}
