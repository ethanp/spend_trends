import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/ui/settings/settings_action_row.dart';

/// Sync settings: the shared connection panel, or a setup hint when `.env`
/// has no sync configuration.
class const SyncStatusTile() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ESettingsSection(
      title: 'Sync',
      children: [
        if (DotEnvSyncBootstrap.isConfigured())
          ESettingsCard(
            child: ESyncConnectionPanel(
              accent: SettingsSectionStyle.sync.accent,
            ),
          )
        else
          const Text(
            'Set POWERSYNC_JWT_SECRET and SERVER_HOST_LAN or '
            'SERVER_HOST_TAILSCALE in .env to enable sync.',
            style: SettingsType.sectionMeta,
          ),
      ],
    );
  }
}
