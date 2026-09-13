import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';

class const BankInstitutionHeader({
  required final Account sampleAccount,
  required final String displayName,
  required final Color accentColor,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<BankInstitutionHeader> createState() =>
      _BankInstitutionHeaderState();
}

class _BankInstitutionHeaderState()
    extends ConsumerState<BankInstitutionHeader> {
  static const _nameEditSlack = 50.0;

  late final TextEditingController _nameController;
  late final FocusNode _focusNode;
  bool _editing = false;
  bool _saving = false;

  bool get _canRename => !widget.sampleAccount.isCopilot;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _focusNode = FocusNode()..addListener(_commitRenameOnFocusLost);
  }

  @override
  void didUpdateWidget(covariant BankInstitutionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.displayName != widget.displayName) {
      _nameController.text = widget.displayName;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_commitRenameOnFocusLost);
    _focusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _commitRenameOnFocusLost() {
    if (_focusNode.hasFocus || !_editing) return;
    _commitRename();
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = EText.body.large.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: -0.2,
      color: widget.accentColor,
    );
    if (!_canRename) {
      return Text(widget.displayName, style: titleStyle);
    }
    final typed = _nameController.text.trim();
    final width = ETextField.widthForText(
      typed.isNotEmpty ? typed : widget.displayName,
      style: titleStyle,
      extra: _nameEditSlack,
    );
    if (_editing) return _renameField(titleStyle, width);
    return GestureDetector(
      onTap: _beginEditing,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Text(widget.displayName, style: titleStyle),
      ),
    );
  }

  Widget _renameField(TextStyle titleStyle, double width) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: _nameController,
        focusNode: _focusNode,
        style: titleStyle,
        decoration: EInput.filled(
          isDense: true,
          hintText: widget.sampleAccount.connName?.trim().isNotEmpty == true
              ? widget.sampleAccount.connName
              : 'Bank name',
          hintStyle: titleStyle.copyWith(color: EColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: ELayout.spaceSm,
            vertical: ELayout.spaceXs,
          ),
          fillColor: EColors.surfaceInset,
          focusedBorder: EInput.outlineSm.copyWith(
            borderSide: BorderSide(color: widget.accentColor),
          ),
        ),
        enabled: !_saving,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _commitRename(),
      ),
    );
  }

  void _beginEditing() {
    setState(() {
      _editing = true;
      _nameController.text = widget.displayName;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  Future<void> _commitRename() async {
    if (!_editing || _saving) return;
    final nextLabel = _nameController.text.trim();
    final official = widget.sampleAccount.connName?.trim() ?? '';
    final unchanged =
        nextLabel == widget.displayName ||
        (nextLabel.isEmpty &&
            (widget.sampleAccount.connUserLabel == null ||
                widget.sampleAccount.connUserLabel!.isEmpty));
    if (unchanged) {
      setState(() => _editing = false);
      return;
    }

    setState(() => _saving = true);
    try {
      final repository = await ref.read(accountsRepositoryProvider.future);
      final storedLabel = nextLabel.isEmpty || nextLabel == official
          ? null
          : nextLabel;
      await repository.updateInstitutionUserLabel(
        account: widget.sampleAccount,
        connUserLabel: storedLabel,
      );
      ref.read(spendDataChangedProvider.notifier).notify();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _editing = false;
        });
      }
    }
  }
}
