import 'package:flutter/material.dart';

import '../../features/household/screens/family_screen.dart';
import '../../features/household/screens/household_home_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/rewards/screens/progress_screen.dart';

/// The 4 top-level destinations shown in the bottom navigation bar on
/// every "signed in" screen, matching the lo-fidelity wireframes.
enum AppTab { home, family, progress, settings }

/// Persistent chrome (app bar + bottom navigation) for the 4 top-level
/// tabs. Built once and kept alive for the whole "signed in" session
/// instead of being rebuilt per tab.
///
/// Switching tabs is a plain [setState] that moves an [IndexedStack]
/// index — it never touches the [Navigator]. Previously each tab screen
/// built its own `Scaffold` + bottom nav bar and switched tabs via
/// `Navigator.pushReplacementNamed`, which tore down and recreated the
/// entire page — bottom nav bar included — on every tap, producing a
/// visible flicker as the old bar was disposed and a new one animated
/// in. Keeping a single shell alive and only swapping the body avoids
/// that, and preserves each tab's scroll position/state as a bonus.
class MainTabShell extends StatefulWidget {
  const MainTabShell({super.key, this.initialTab = AppTab.home});

  final AppTab initialTab;

  /// Switches the visible tab of the nearest [MainTabShell] ancestor
  /// without pushing a new route (e.g. a "jump to Progress" shortcut
  /// from within another tab).
  static void switchTab(BuildContext context, AppTab tab) {
    context.findAncestorStateOfType<_MainTabShellState>()?._switchTab(tab);
  }

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class _MainTabShellState extends State<MainTabShell> {
  late AppTab _currentTab = widget.initialTab;

  // Built once and kept alive inside the IndexedStack below so switching
  // tabs never disposes/rebuilds a tab's widget tree (or the nav bar).
  static const _tabBodies = <Widget>[
    HouseholdHomeScreen(),
    FamilyScreen(),
    ProgressScreen(),
    ProfileScreen(),
  ];

  void _switchTab(AppTab tab) {
    if (tab == _currentTab) return;
    setState(() => _currentTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Famotive'), centerTitle: true),
      body: SafeArea(
        child: IndexedStack(index: _currentTab.index, children: _tabBodies),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab.index,
        onDestinationSelected: (index) => _switchTab(AppTab.values[index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Family'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
