import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/features/projections/fire_outlook_card.dart';
import 'package:spend_trends/features/banks/banks_advanced_section.dart';
import 'package:spend_trends/features/settings/copilot_import_tile.dart';
import 'package:spend_trends/features/settings/remove_duplicate_transactions_tile.dart';
import 'package:spend_trends/features/settings/settings_action_row.dart';
import 'package:spend_trends/features/settings/sync_status_tile.dart';

class const SettingsScreen() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Settings',
        leading: ESyncPhaseIcon(),
        automaticallyImplyLeading: false,
        actions: [FireOutlookCard()],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: ETabBarOverlay.paddingOf(
            context,
            contentPadding: const EdgeInsets.fromLTRB(
              ELayout.spaceLg,
              ELayout.spaceMd,
              ELayout.spaceLg,
              32,
            ),
          ),
          children: [
            const BanksAdvancedSection(),
            const SizedBox(height: ELayout.spaceXl),
            const SyncStatusTile(),
            const SizedBox(height: ELayout.spaceXl),
            const ESettingsSection(
              title: 'Copilot migration',
              children: [
                ESettingsRowGroup(
                  children: [
                    CopilotImportTile(),
                    RemoveDuplicateTransactionsTile(),
                  ],
                ),
              ],
            ),
            const SizedBox(height: ELayout.spaceXl),
            ESettingsSection(
              title: 'Diagnostics',
              children: [
                ESettingsRowGroup(
                  children: [
                    EAppLogRow(
                      eyebrow: AppIdentity.displayName,
                      accent: SettingsSectionStyle.sync.accent,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
