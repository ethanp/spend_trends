import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/theme/finance_colors.dart';

class const CategoryEditorIdentityFields({
  required final TextEditingController nameController,
  required final bool autofocus,
  required final List<CategoryGroup> groups,
  required final String? selectedGroupId,
  required final ValueChanged<String?> onGroupSelected,
  required final ConsciousSpendingArea? selectedArea,
  required final ValueChanged<ConsciousSpendingArea?> onAreaSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CategoryEditorNameField(
          nameController: nameController,
          autofocus: autofocus,
        ),
        const SizedBox(height: ELayout.spaceMd),
        CategoryEditorGroupPicker(
          groups: groups,
          selectedGroupId: selectedGroupId,
          onGroupSelected: onGroupSelected,
        ),
        const SizedBox(height: ELayout.spaceMd),
        CategoryEditorAreaPicker(
          selectedArea: selectedArea,
          onAreaSelected: onAreaSelected,
        ),
      ],
    );
  }
}

class const CategoryEditorNameField({
  required final TextEditingController nameController,
  required final bool autofocus,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: nameController,
      autofocus: autofocus,
      style: EText.body.medium.copyWith(color: EColors.textPrimary),
      decoration: EInput.filled(hintText: 'Name'),
    );
  }
}

class const CategoryEditorGroupPicker({
  required final List<CategoryGroup> groups,
  required final String? selectedGroupId,
  required final ValueChanged<String?> onGroupSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Group', style: EText.caption),
        const SizedBox(height: ELayout.spaceXs),
        Wrap(
          spacing: ELayout.spaceSm,
          runSpacing: ELayout.spaceSm,
          children: [
            CategoryEditorGroupChip(
              label: 'None',
              isSelected: selectedGroupId == null,
              onActivated: () => onGroupSelected(null),
            ),
            for (final group in groups)
              CategoryEditorGroupChip(
                label: group.name,
                isSelected: selectedGroupId == group.id,
                onActivated: () => onGroupSelected(group.id),
              ),
          ],
        ),
      ],
    );
  }
}

class const CategoryEditorAreaPicker({
  required final ConsciousSpendingArea? selectedArea,
  required final ValueChanged<ConsciousSpendingArea?> onAreaSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Area', style: EText.caption),
        const SizedBox(height: ELayout.spaceXs),
        Wrap(
          spacing: ELayout.spaceSm,
          runSpacing: ELayout.spaceSm,
          children: [
            CategoryEditorGroupChip(
              label: 'None',
              isSelected: selectedArea == null,
              onActivated: () => onAreaSelected(null),
            ),
            for (final area in ConsciousSpendingArea.values)
              CategoryEditorGroupChip(
                label: area.displayName,
                isSelected: selectedArea == area,
                onActivated: () => onAreaSelected(area),
              ),
          ],
        ),
      ],
    );
  }
}

class const CategoryEditorGroupChip({
  required final String label,
  required final bool isSelected,
  required final VoidCallback onActivated,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onActivated,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ELayout.spaceMd,
          vertical: ELayout.spaceSm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? FinanceColors.accentPrimary : EColors.surface,
          borderRadius: ELayout.borderRadiusSm,
          border: Border.all(
            color: isSelected ? FinanceColors.accentPrimary : EColors.border,
          ),
        ),
        child: Text(
          label,
          style: EText.caption.copyWith(
            color: isSelected ? EColors.textPrimary : EColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
