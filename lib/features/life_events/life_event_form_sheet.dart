import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/life_events_repository.dart';
import 'package:spend_trends/widgets/app_date_field.dart';
import 'package:spend_trends/widgets/app_date_picker.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

enum _LifeEventDateMode() {
  day,
  range,
  ongoing,
}

class const LifeEventFormSheet({final LifeEvent? lifeEvent})
    extends ConsumerStatefulWidget {
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    LifeEvent? lifeEvent,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LifeEventFormSheet(lifeEvent: lifeEvent),
    );
  }

  @override
  ConsumerState<LifeEventFormSheet> createState() => _LifeEventFormSheetState();
}

class _LifeEventFormSheetState() extends ConsumerState<LifeEventFormSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _startedOn;
  late DateTime _endedOn;
  late _LifeEventDateMode _dateMode;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.lifeEvent != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.lifeEvent;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _startedOn = (existing?.startedOn ?? DateTime.now()).startOfDay;
    _endedOn = (existing?.endedOn ?? _startedOn).startOfDay;
    if (existing == null) {
      _dateMode = _LifeEventDateMode.day;
    } else if (existing.isOpenEnded) {
      _dateMode = _LifeEventDateMode.ongoing;
    } else if (existing.isClosedRange) {
      _dateMode = _LifeEventDateMode.range;
    } else {
      _dateMode = _LifeEventDateMode.day;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
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
              const SizedBox(height: ELayout.spaceMd),
              _titleField(),
              const SizedBox(height: ELayout.spaceMd),
              _dateModeControl(),
              const SizedBox(height: ELayout.spaceMd),
              AppDateField(
                label: _dateMode == _LifeEventDateMode.day ? 'Date' : 'Start',
                date: _startedOn,
                onActivated: () => _pickDate(isStart: true),
              ),
              if (_dateMode == _LifeEventDateMode.range) ...[
                const SizedBox(height: ELayout.spaceSm),
                AppDateField(
                  label: 'End',
                  date: _endedOn,
                  onActivated: () => _pickDate(isStart: false),
                ),
              ],
              const SizedBox(height: ELayout.spaceMd),
              _noteField(),
              if (_error != null) ...[
                const SizedBox(height: ELayout.spaceSm),
                Text(
                  _error!,
                  style: EText.caption.copyWith(color: EColors.danger),
                ),
              ],
              const SizedBox(height: ELayout.spaceMd),
              _saveButton(),
              if (_isEditing) ...[
                const SizedBox(height: ELayout.spaceSm),
                _deleteButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader() {
    return Text(
      _isEditing ? 'Edit life event' : 'New life event',
      style: EText.section,
    );
  }

  Widget _titleField() {
    return TextField(
      controller: _titleController,
      autofocus: !_isEditing,
      style: EText.body.medium.copyWith(color: EColors.textPrimary),
      decoration: EInput.filled(hintText: 'Title'),
    );
  }

  Widget _dateModeControl() {
    return SegmentedButton<_LifeEventDateMode>(
      segments: const [
        ButtonSegment(value: _LifeEventDateMode.day, label: Text('Day')),
        ButtonSegment(value: _LifeEventDateMode.range, label: Text('Range')),
        ButtonSegment(
          value: _LifeEventDateMode.ongoing,
          label: Text('Ongoing'),
        ),
      ],
      selected: {_dateMode},
      onSelectionChanged: (selection) {
        final mode = selection.first;
        setState(() {
          _dateMode = mode;
          if (mode == _LifeEventDateMode.range &&
              _endedOn.isBefore(_startedOn)) {
            _endedOn = _startedOn;
          }
        });
      },
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

  Widget _deleteButton() {
    return TextButton(
      onPressed: _busy ? null : _confirmDelete,
      style: TextButton.styleFrom(foregroundColor: EColors.danger),
      child: const Text('Delete'),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await pickAppDate(
      context,
      initialDate: isStart ? _startedOn : _endedOn,
      minimumDate: isStart ? null : _startedOn,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startedOn = picked;
        if (_endedOn.isBefore(_startedOn)) {
          _endedOn = _startedOn;
        }
      } else {
        _endedOn = picked;
      }
    });
  }

  DateTime? get _endedOnForSave {
    switch (_dateMode) {
      case _LifeEventDateMode.day:
        return _startedOn;
      case _LifeEventDateMode.range:
        return _endedOn.isBefore(_startedOn) ? _startedOn : _endedOn;
      case _LifeEventDateMode.ongoing:
        return null;
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repository = await ref.read(lifeEventsRepositoryProvider.future);
      if (_isEditing) {
        await repository.upsert(
          LifeEvent(
            id: widget.lifeEvent!.id,
            title: title,
            startedOn: _startedOn,
            endedOn: _endedOnForSave,
            note: _noteController.text,
          ),
        );
      } else {
        await repository.create(
          title: title,
          startedOn: _startedOn,
          endedOn: _endedOnForSave,
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
        title: const Text('Delete life event?'),
        content: Text('“${widget.lifeEvent!.title}” will be removed.'),
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
      final repository = await ref.read(lifeEventsRepositoryProvider.future);
      await repository.delete(widget.lifeEvent!.id);
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
