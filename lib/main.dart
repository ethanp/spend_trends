import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/agent_api/agent_api_server.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/features/activity/activity_screen.dart';
import 'package:spend_trends/features/banks/banks_screen.dart';
import 'package:spend_trends/features/categories/categories_screen.dart';
import 'package:spend_trends/features/life_events/life_events_screen.dart';
import 'package:spend_trends/features/projections/projections_screen.dart';
import 'package:spend_trends/features/settings/settings_screen.dart';
import 'package:spend_trends/features/trends/trends_screen.dart';
import 'package:spend_trends/services/sync/sync_config.dart';

const _mainTabs = <EMainTab>[
  EMainTab(icon: Icons.bar_chart, label: 'Trends', screen: TrendsScreen()),
  EMainTab(
    icon: Icons.trending_up,
    label: 'Projections',
    screen: ProjectionsScreen(),
  ),
  EMainTab(icon: Icons.account_balance, label: 'Banks', screen: BanksScreen()),
  EMainTab(icon: Icons.flag, label: 'Life Events', screen: LifeEventsScreen()),
  EMainTab(icon: Icons.list, label: 'Activity', screen: ActivityScreen()),
  EMainTab(icon: Icons.label, label: 'Categories', screen: CategoriesScreen()),
  EMainTab(icon: Icons.settings, label: 'Settings', screen: SettingsScreen()),
];

void main() {
  const SyncedAppLaunch(
    appName: AppIdentity.displayName,
    syncConfig: buildSpendTrendsSyncConfig,
    home: EMainTabScreen(tabs: _mainTabs),
    beforeRunApp: AgentApiServer.startFromEnv,
  ).launch();
}
