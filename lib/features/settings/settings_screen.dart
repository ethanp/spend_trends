import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/features/banks/banks_advanced_section.dart';
import 'package:spend_trends/features/settings/copilot_import_tile.dart';
import 'package:spend_trends/features/settings/csv_import_sheet.dart';
import 'package:spend_trends/features/settings/remove_duplicate_transactions_tile.dart';
import 'package:spend_trends/features/settings/unlock_copilot_categories_tile.dart';
import 'package:spend_trends/features/settings/settings_section.dart';
import 'package:spend_trends/features/settings/sync_status_tile.dart';
import 'package:spend_trends/widgets/sync_status_nav_button.dart';

class const SettingsScreen() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Settings',
        leading: SyncStatusNavButton(),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ELayout.spaceLg,
            ELayout.spaceMd,
            ELayout.spaceLg,
            32,
          ).withOverlaidTabBar(context),
          children: [
            const BanksAdvancedSection(),
            const SizedBox(height: ELayout.spaceXl),
            const SettingsHairline(style: SettingsSectionStyle.banks),
            const SizedBox(height: ELayout.spaceXl),
            const SyncStatusTile(),
            const SizedBox(height: ELayout.spaceXl),
            const SettingsHairline(style: SettingsSectionStyle.sync),
            const SizedBox(height: ELayout.spaceXl),
            const SettingsSectionHeader(
              icon: Icons.build,
              title: 'Maintenance',
              style: SettingsSectionStyle.maintenance,
            ),
            const SizedBox(height: ELayout.spaceLg),
            const CopilotImportTile(),
            const SizedBox(height: ELayout.spaceLg),
            const UnlockCopilotCategoriesTile(),
            const SizedBox(height: ELayout.spaceLg),
            const RemoveDuplicateTransactionsTile(),
            const SizedBox(height: ELayout.spaceLg),
            SettingsToolRow(
              icon: Icons.description,
              title: 'Import CSV',
              caption: 'Escape hatch when a bank connection is broken.',
              onActivated: () => CsvImportSheet.show(context),
              style: SettingsSectionStyle.maintenance,
            ),
            const SizedBox(height: ELayout.spaceXl),
            const SettingsHairline(style: SettingsSectionStyle.maintenance),
            const SizedBox(height: ELayout.spaceLg),
            const Text(
              'Budgets — personal spending by category with SimpleFIN.',
              style: SettingsType.sectionMeta,
            ),
          ],
        ),
      ),
    );
  }
}
