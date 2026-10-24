import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/manual_accounts.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/widgets/app_date_field.dart';
import 'package:spend_trends/widgets/app_date_picker.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

/// Adds a manual account, or records a new balance on [account].
class const ManualAccountFormSheet({final Account? account})
    extends ConsumerStatefulWidget {
  static Future<void> show(BuildContext context, {Account? account}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualAccountFormSheet(account: account),
    );
  }

  @override
  ConsumerState<ManualAccountFormSheet> createState() =>
      _ManualAccountFormSheetState();
}

class _ManualAccountFormSheetState()
    extends ConsumerState<ManualAccountFormSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _institutionController = TextEditingController();
  final TextEditingController _balanceController = TextEditingController();
  AccountKind _kind = AccountKind.investment;
  DateTime _recordedOn = DateTime.now().startOfDay;
  bool _busy = false;
  String? _error;

  bool get _isRecordingBalance => widget.account != null;

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _balanceController.dispose();
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
                _isRecordingBalance
                    ? 'Update balance · ${widget.account!.displayName}'
                    : 'Add manual account',
                style: EText.section,
              ),
              if (!_isRecordingBalance) ..._accountFields(),
              const SizedBox(height: ELayout.spaceMd),
              _textField(
                _balanceController,
                hintText: 'Balance (dollars)',
                autofocus: _isRecordingBalance,
                numeric: true,
              ),
              const SizedBox(height: ELayout.spaceMd),
              AppDateField(
                label: 'As of',
                date: _recordedOn,
                onActivated: _pickRecordedOn,
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
                child: Text(_isRecordingBalance ? 'Save' : 'Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _accountFields() {
    return [
      const SizedBox(height: ELayout.spaceMd),
      _textField(
        _nameController,
        hintText: 'Name (e.g. HSA, Bitcoin)',
        autofocus: true,
      ),
      const SizedBox(height: ELayout.spaceMd),
      _textField(_institutionController, hintText: 'Institution (optional)'),
      const SizedBox(height: ELayout.spaceMd),
      DropdownButtonFormField<AccountKind>(
        initialValue: _kind,
        isDense: true,
        decoration: EInput.filled(),
        style: EText.body.medium.copyWith(color: EColors.textPrimary),
        items: [
          for (final kind in AccountKind.values)
            DropdownMenuItem(value: kind, child: Text(kind.legendLabel)),
        ],
        onChanged: (selected) {
          if (selected != null) setState(() => _kind = selected);
        },
      ),
    ];
  }

  Widget _textField(
    TextEditingController controller, {
    required String hintText,
    bool autofocus = false,
    bool numeric = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : null,
      style: EText.body.medium.copyWith(color: EColors.textPrimary),
      decoration: EInput.filled(hintText: hintText),
    );
  }

  Future<void> _pickRecordedOn() async {
    final picked = await pickAppDate(context, initialDate: _recordedOn);
    if (picked == null || !mounted) return;
    setState(() => _recordedOn = picked.startOfDay);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (!_isRecordingBalance && name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final int balanceCents;
    try {
      balanceCents = _balanceController.text.asCents;
    } on FormatException {
      setState(() => _error = 'Enter a dollar amount.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ManualAccounts manualAccounts = await ref.read(
        manualAccountsProvider.future,
      );
      final account =
          widget.account ??
          await manualAccounts.create(
            name: name,
            kind: _kind,
            institution: _institutionController.text.trim().isEmpty
                ? null
                : _institutionController.text.trim(),
          );
      await manualAccounts.recordBalance(
        account: account,
        balanceCents: balanceCents,
        recordedOn: _recordedOn,
      );
      ref.read(spendDataChangedProvider.notifier).notify();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
