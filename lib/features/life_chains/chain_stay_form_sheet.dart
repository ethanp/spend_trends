import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/chain_stays_repository.dart';
import 'package:spend_trends/widgets/app_date_field.dart';
import 'package:spend_trends/widgets/app_date_picker.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

class const ChainStayFormSheet({
  required final LifeChainKind kind,
  final ChainStay? stay,

  /// Suggested move-in/start day when creating (e.g. day before the oldest stay).
  final DateTime? initialStartedOn,
}) extends ConsumerStatefulWidget {
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    required LifeChainKind kind,
    ChainStay? stay,
    DateTime? initialStartedOn,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChainStayFormSheet(
        kind: kind,
        stay: stay,
        initialStartedOn: initialStartedOn,
      ),
    );
  }

  @override
  ConsumerState<ChainStayFormSheet> createState() => _ChainStayFormSheetState();
}

class _ChainStayFormSheetState() extends ConsumerState<ChainStayFormSheet> {
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  late DateTime _startedOn;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.stay != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.stay;
    _labelController = TextEditingController(text: existing?.label ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _startedOn =
        (existing?.startedOn ?? widget.initialStartedOn ?? DateTime.now())
            .startOfDay;
  }

  @override
  void dispose() {
    _labelController.dispose();
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
              Text(
                _isEditing
                    ? 'Edit ${widget.kind.screenTitle.toLowerCase()}'
                    : widget.kind.addCta,
                style: EText.section,
              ),
              const SizedBox(height: ELayout.spaceMd),
              TextField(
                controller: _labelController,
                autofocus: !_isEditing,
                style: EText.body.medium.copyWith(color: EColors.textPrimary),
                decoration: EInput.filled(
                  hintText: widget.kind.labelPlaceholder,
                ),
              ),
              const SizedBox(height: ELayout.spaceMd),
              AppDateField(
                label: widget.kind.startDateLabel,
                date: _startedOn,
                onActivated: _pickDate,
              ),
              const SizedBox(height: ELayout.spaceMd),
              TextField(
                controller: _noteController,
                maxLines: 3,
                minLines: 2,
                style: EText.body.medium.copyWith(color: EColors.textPrimary),
                decoration: EInput.filled(hintText: 'Note (optional)'),
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
                child: Text(_isEditing ? 'Save' : 'Add'),
              ),
              if (_isEditing) ...[
                const SizedBox(height: ELayout.spaceSm),
                TextButton(
                  onPressed: _busy ? null : _confirmDelete,
                  style: TextButton.styleFrom(foregroundColor: EColors.danger),
                  child: const Text('Delete'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await pickAppDate(context, initialDate: _startedOn);
    if (picked == null || !mounted) return;
    setState(() => _startedOn = picked);
  }

  Future<ChainStaysRepository> _repository() async {
    return switch (widget.kind) {
      LifeChainKind.housing => ref.read(housingStaysRepositoryProvider.future),
      LifeChainKind.job => ref.read(jobStaysRepositoryProvider.future),
    };
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _error = '${widget.kind.labelPlaceholder} is required.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = await _repository();
      if (_isEditing) {
        await repository.upsert(
          ChainStay(
            id: widget.stay!.id,
            label: label,
            startedOn: _startedOn,
            note: _noteController.text,
          ),
        );
      } else {
        await repository.create(
          label: label,
          startedOn: _startedOn,
          note: _noteController.text,
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${widget.kind.screenTitle.toLowerCase()} stay?'),
        content: Text('“${widget.stay!.label}” will be removed.'),
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
      final repository = await _repository();
      await repository.delete(widget.stay!.id);
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
