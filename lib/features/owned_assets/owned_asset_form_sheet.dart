import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/owned_assets_repository.dart';
import 'package:spend_trends/widgets/app_date_field.dart';
import 'package:spend_trends/widgets/app_date_picker.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

class const OwnedAssetFormSheet({
  final OwnedAssetWithValuations? ownedAsset,
  final bool updateValueOnly = false,
}) extends ConsumerStatefulWidget {
  static Future<void> show(
    BuildContext context, {
    OwnedAssetWithValuations? ownedAsset,
    bool updateValueOnly = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OwnedAssetFormSheet(
        ownedAsset: ownedAsset,
        updateValueOnly: updateValueOnly,
      ),
    );
  }

  @override
  ConsumerState<OwnedAssetFormSheet> createState() =>
      _OwnedAssetFormSheetState();
}

class _OwnedAssetFormSheetState() extends ConsumerState<OwnedAssetFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late final TextEditingController _noteController;
  late OwnedAssetKind _kind;
  late DateTime _valuedOn;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.ownedAsset != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.ownedAsset;
    _nameController = TextEditingController(text: existing?.asset.name ?? '');
    _noteController = TextEditingController(text: existing?.asset.note ?? '');
    _kind = existing?.asset.kind ?? OwnedAssetKind.home;
    _valuedOn = (existing?.currentValuedOn ?? DateTime.now()).startOfDay;
    _valueController = TextEditingController(
      text: existing == null
          ? ''
          : (existing.currentValueCents / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetPanel.compact(
      child: Padding(
        padding: const EdgeInsets.all(ELayout.spaceLg),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(),
              if (!widget.updateValueOnly) ...[
                const SizedBox(height: ELayout.spaceMd),
                _nameField(),
                const SizedBox(height: ELayout.spaceMd),
                _kindControl(),
              ],
              const SizedBox(height: ELayout.spaceMd),
              _valueField(),
              const SizedBox(height: ELayout.spaceMd),
              AppDateField(
                label: 'Valued on',
                date: _valuedOn,
                onActivated: _pickValuedOn,
              ),
              if (!widget.updateValueOnly) ...[
                const SizedBox(height: ELayout.spaceMd),
                _noteField(),
              ],
              if (_error != null) ...[
                const SizedBox(height: ELayout.spaceSm),
                Text(
                  _error!,
                  style: EText.caption.copyWith(color: EColors.danger),
                ),
              ],
              const SizedBox(height: ELayout.spaceMd),
              _saveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader() {
    if (widget.updateValueOnly) {
      return Text('Update value', style: EText.section);
    }
    return Text(
      _isEditing ? 'Edit owned asset' : 'Add owned asset',
      style: EText.section,
    );
  }

  Widget _nameField() {
    return TextField(
      controller: _nameController,
      autofocus: !_isEditing,
      style: EText.body.medium.copyWith(color: EColors.textPrimary),
      decoration: EInput.filled(hintText: 'Name (e.g. Home, Car)'),
    );
  }

  Widget _kindControl() {
    return SegmentedButton<OwnedAssetKind>(
      segments: [
        for (final kind in OwnedAssetKind.values)
          ButtonSegment(value: kind, label: Text(kind.legendLabel)),
      ],
      selected: {_kind},
      onSelectionChanged: (selection) {
        setState(() => _kind = selection.first);
      },
    );
  }

  Widget _valueField() {
    return TextField(
      controller: _valueController,
      autofocus: widget.updateValueOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: EText.body.medium.copyWith(color: EColors.textPrimary),
      decoration: EInput.filled(hintText: 'Value (dollars)'),
    );
  }

  Widget _noteField() {
    return TextField(
      controller: _noteController,
      maxLines: 3,
      minLines: 2,
      style: EText.body.medium.copyWith(color: EColors.textPrimary),
      decoration: EInput.filled(hintText: 'Note (optional)'),
    );
  }

  Widget _saveButton() {
    return AppPrimaryButton(
      busy: _busy,
      onPressed: _save,
      child: Text(_isEditing ? 'Save' : 'Add'),
    );
  }

  Future<void> _pickValuedOn() async {
    final picked = await pickAppDate(context, initialDate: _valuedOn);
    if (picked == null || !mounted) return;
    setState(() => _valuedOn = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (!widget.updateValueOnly && name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }

    final int valueCents;
    try {
      valueCents = _valueController.text.asCents;
    } on FormatException {
      setState(() => _error = 'Enter a dollar amount.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repository = await ref.read(ownedAssetsRepositoryProvider.future);
      if (!_isEditing) {
        await repository.create(
          name: name,
          kind: _kind,
          valueCents: valueCents,
          valuedOn: _valuedOn,
          note: _noteController.text,
        );
      } else {
        await _saveExisting(
          repository: repository,
          name: name,
          valueCents: valueCents,
        );
      }
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveExisting({
    required OwnedAssetsRepository repository,
    required String name,
    required int valueCents,
  }) async {
    final existing = widget.ownedAsset!;
    if (!widget.updateValueOnly) {
      await repository.updateAsset(
        existing.asset.copyWith(
          name: name,
          kind: _kind,
          note: _noteController.text,
          clearNote: _noteController.text.trim().isEmpty,
        ),
      );
    }
    final valueChanged = valueCents != existing.currentValueCents;
    final dateChanged =
        _valuedOn.startOfDay != existing.currentValuedOn?.startOfDay;
    if (valueChanged || dateChanged) {
      await repository.appendValuation(
        ownedAssetId: existing.asset.id,
        valueCents: valueCents,
        valuedOn: _valuedOn,
      );
    }
  }
}
