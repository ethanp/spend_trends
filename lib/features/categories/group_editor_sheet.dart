import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

/// Create or edit a category group name.
class const GroupEditorSheet({final CategoryGroup? group})
    extends ConsumerStatefulWidget {
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    CategoryGroup? group,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupEditorSheet(group: group),
    );
  }

  @override
  ConsumerState<GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _GroupEditorSheetState() extends ConsumerState<GroupEditorSheet> {
  late final TextEditingController _nameController;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.group != null;

  bool get _isIncomeGroup => SpecialCategory.isIncomeGroupId(widget.group?.id);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetPanel.compact(
      child: Padding(
        padding: const EdgeInsets.all(ELayout.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEditing ? 'Edit group' : 'New group', style: EText.section),
            const SizedBox(height: ELayout.spaceMd),
            TextField(
              controller: _nameController,
              autofocus: !_isEditing,
              style: EText.body.medium.copyWith(color: EColors.textPrimary),
              decoration: EInput.filled(hintText: 'Name (e.g. Wants)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: ELayout.spaceSm),
              Text(
                _error!,
                style: EText.caption.copyWith(color: EColors.danger),
              ),
            ],
            const SizedBox(height: ELayout.spaceMd),
            AppPrimaryButton(
              busy: _busy,
              onPressed: _save,
              child: Text(_isEditing ? 'Save' : 'Create'),
            ),
            if (_isEditing && !_isIncomeGroup) ...[
              const SizedBox(height: ELayout.spaceSm),
              TextButton(
                onPressed: _busy ? null : _confirmDelete,
                style: TextButton.styleFrom(foregroundColor: EColors.danger),
                child: const Text('Delete group'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repository = await ref.read(categoriesRepositoryProvider.future);
      if (_isEditing) {
        await repository.renameGroup(groupId: widget.group!.id, name: name);
      } else {
        await repository.createGroup(name: name);
      }
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
          '“${widget.group!.name}” will be removed. '
          'Categories stay; they just leave the group.',
        ),
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = await ref.read(categoriesRepositoryProvider.future);
      await repository.deleteGroup(widget.group!.id);
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
