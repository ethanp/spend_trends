import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/theme/finance_colors.dart';

/// Per-section accent used for action row icons and progress.
class const SettingsSectionStyle({required final Color accent}) {
  /// Banks — teal (money / SimpleFIN).
  static const banks = SettingsSectionStyle(
    accent: FinanceColors.accentPrimary,
  );

  /// Sync — cool indigo (near console chrome).
  static const sync = SettingsSectionStyle(accent: Color(0xFF7B8CDE));

  /// Copilot migration — muted clay (not bright yellow).
  static const copilotMigration = SettingsSectionStyle(
    accent: Color(0xFF9A7B6A),
  );
}

/// Type roles for Settings captions.
class SettingsType._() {
  static const sectionMeta = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: EColors.textMuted,
    height: 1.35,
  );
}

/// A standard settings row that runs a task: accent icon, title, one caption.
/// While [busy], a progress ring replaces the icon and [message] replaces the
/// caption, so the row keeps its height.
class const SettingsActionRow({
  required final IconData icon,
  required final String title,
  required final String caption,
  required final VoidCallback? onActivated,
  required final SettingsSectionStyle style,
  final bool busy = false,

  /// Progress or result text; shown in place of [caption] when set.
  final String? message,

  /// Determinate ring while [busy]; null spins.
  final double? progressFraction,
  final VoidCallback? onCancel,
}) extends StatelessWidget {
  static const _iconSize = 24.0;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: busy
          ? SizedBox.square(
              dimension: _iconSize,
              child: CircularProgressIndicator(
                value: progressFraction,
                strokeWidth: 2,
                color: style.accent,
              ),
            )
          : Icon(icon, size: _iconSize, color: style.accent),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        message ?? caption,
        style: const TextStyle(color: EColors.textMuted),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _trailingAction(),
      onTap: busy ? null : onActivated,
    );
  }

  Widget? _trailingAction() {
    if (!busy) {
      return const Icon(Icons.chevron_right, color: EColors.textMuted);
    }
    if (onCancel == null) return null;
    return TextButton(
      onPressed: onCancel,
      child: Text('Cancel', style: TextStyle(color: style.accent)),
    );
  }
}
