import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A bank or account name that turns into a rename field when tapped.
///
/// ✓ or Return saves, and so does clicking elsewhere on the Mac. ✕ or Esc
/// cancels and keeps the current name. iOS keeps the field focused on an
/// outside tap, so ✓ and ✕ are the phone's ways out. [onRenameConfirmed] gets
/// the trimmed text and decides whether anything changed.
class const BankNameRenameField({
  required final String displayName,
  required final String hintText,
  required final TextStyle nameStyle,
  required final Color accentColor,
  required final Future<void> Function(String typedName) onRenameConfirmed,
}) extends StatefulWidget {
  @override
  State<BankNameRenameField> createState() => _BankNameRenameFieldState();
}

class _BankNameRenameFieldState() extends State<BankNameRenameField> {
  /// Trailing room past the current name for the tap target / field.
  static const _nameEditSlack = 50.0;
  static const _editActionExtent = 36.0;
  static const _editActionsWidth = _editActionExtent * 2 + ELayout.spaceSm * 2;

  late final TextEditingController _nameController;
  late final FocusNode _focusNode;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _focusNode = FocusNode()..addListener(_saveOnFocusLost);
  }

  @override
  void didUpdateWidget(covariant BankNameRenameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.displayName != widget.displayName) {
      _nameController.text = widget.displayName;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_saveOnFocusLost);
    _focusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _saveOnFocusLost() {
    if (_focusNode.hasFocus || !_editing) return;
    _saveRename();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerLeft,
        child: _nameOrEditor(availableWidth: constraints.maxWidth),
      ),
    );
  }

  Widget _nameOrEditor({required double availableWidth}) {
    final typed = _nameController.text.trim();
    final nameWidth = ETextField.widthForText(
      typed.isNotEmpty ? typed : widget.displayName,
      style: widget.nameStyle,
      extra: _nameEditSlack,
    );
    if (_editing) return _renameEditor(nameWidth, availableWidth);
    return GestureDetector(
      onTap: _beginEditing,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: nameWidth.clamp(0.0, availableWidth),
        child: Text(widget.displayName, style: widget.nameStyle),
      ),
    );
  }

  Widget _renameEditor(double nameWidth, double availableWidth) {
    final fieldMaxWidth = (availableWidth - _editActionsWidth).clamp(
      0.0,
      double.infinity,
    );
    return TextFieldTapRegion(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: nameWidth.clamp(0.0, fieldMaxWidth),
            child: _nameField(),
          ),
          const SizedBox(width: ELayout.spaceSm),
          _editAction(
            icon: Icons.check,
            tooltip: 'Save name',
            fill: widget.accentColor,
            ink: widget.accentColor.computeLuminance() > 0.5
                ? Colors.black
                : Colors.white,
            onPressed: _saveRename,
          ),
          const SizedBox(width: ELayout.spaceSm),
          _editAction(
            icon: Icons.close,
            tooltip: 'Cancel rename',
            fill: EColors.surfaceRaised,
            ink: EColors.textPrimary,
            onPressed: _cancelRename,
          ),
        ],
      ),
    );
  }

  Widget _nameField() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancelRename,
      },
      child: TextField(
        controller: _nameController,
        focusNode: _focusNode,
        style: widget.nameStyle,
        decoration: EInput.filled(
          isDense: true,
          hintText: widget.hintText,
          hintStyle: widget.nameStyle.copyWith(color: EColors.textMuted),
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
        onSubmitted: (_) => _saveRename(),
      ),
    );
  }

  Widget _editAction({
    required IconData icon,
    required String tooltip,
    required Color fill,
    required Color ink,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: _saving ? null : onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: ink,
        fixedSize: const Size.square(_editActionExtent),
        minimumSize: const Size.square(_editActionExtent),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(
          borderRadius: ELayout.borderRadiusSm,
        ),
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

  void _cancelRename() {
    if (!_editing || _saving) return;
    setState(() {
      _editing = false;
      _nameController.text = widget.displayName;
    });
    _focusNode.unfocus();
  }

  Future<void> _saveRename() async {
    if (!_editing || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onRenameConfirmed(_nameController.text.trim());
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
