import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/features/activity/activity_screen.dart';
import 'package:spend_trends/features/banks/banks_screen.dart';
import 'package:spend_trends/features/categories/categories_screen.dart';
import 'package:spend_trends/features/life_events/life_events_screen.dart';
import 'package:spend_trends/features/projections/projections_screen.dart';
import 'package:spend_trends/features/settings/settings_screen.dart';
import 'package:spend_trends/features/trends/trends_screen.dart';

class const MainTab({
  required final IconData icon,
  required final String label,
  required final Widget screen,
});

const mainTabs = <MainTab>[
  MainTab(icon: Icons.bar_chart, label: 'Trends', screen: TrendsScreen()),
  MainTab(
    icon: Icons.trending_up,
    label: 'Projections',
    screen: ProjectionsScreen(),
  ),
  MainTab(icon: Icons.account_balance, label: 'Banks', screen: BanksScreen()),
  MainTab(icon: Icons.flag, label: 'Life Events', screen: LifeEventsScreen()),
  MainTab(icon: Icons.list, label: 'Activity', screen: ActivityScreen()),
  MainTab(icon: Icons.label, label: 'Categories', screen: CategoriesScreen()),
  MainTab(icon: Icons.settings, label: 'Settings', screen: SettingsScreen()),
];

class const MainTabScreen() extends StatefulWidget {
  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState() extends State<MainTabScreen> {
  int _selectedTabIndex = 0;
  final _navigatorKeys = List<GlobalKey<NavigatorState>>.generate(
    mainTabs.length,
    (_) => GlobalKey<NavigatorState>(),
  );

  @override
  Widget build(BuildContext context) {
    return EScaffoldShell(
      contentMaxWidth: double.infinity,
      bottomBar: ETabBar(
        selectedIndex: _selectedTabIndex,
        tabs: [
          for (final tab in mainTabs) ETab(icon: tab.icon, label: tab.label),
        ],
        onSelected: (index) {
          if (index == _selectedTabIndex) {
            _navigatorKeys[index].currentState?.popUntil(
              (route) => route.isFirst,
            );
            return;
          }
          setState(() => _selectedTabIndex = index);
        },
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          for (var tabIndex = 0; tabIndex < mainTabs.length; tabIndex++)
            Navigator(
              key: _navigatorKeys[tabIndex],
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => mainTabs[tabIndex].screen,
              ),
            ),
        ],
      ),
    );
  }
}
