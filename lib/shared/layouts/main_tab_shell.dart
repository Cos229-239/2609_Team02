import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import '../../features/household/screens/family_screen.dart';
import '../../features/household/screens/household_home_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/rewards/screens/progress_screen.dart';
import '../../features/tasks/screens/child_home_screen.dart';
import '../../features/tasks/screens/child_rewards_screen.dart';
import '../../features/tasks/screens/child_tasks_screen.dart';

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

  // Kept alive inside the IndexedStack below so switching tabs never
  // disposes/rebuilds a tab's widget tree (or the nav bar). Based on the
  // signed-in user's role: the 1st slot swaps between the parent and
  // child home dashboards, the 2nd between the parent's "Family"
  // management screen and the child's "Tasks" (claim/complete/history)
  // screen, and the 3rd between the family-wide "Progress" screen and
  // the child's "Rewards" screen (leaderboard + reward catalog) — a
  // child never sees the household-management or task-creation UI.
  static const _parentTabBodies = <Widget>[
    HouseholdHomeScreen(),
    FamilyScreen(),
    ProgressScreen(),
    ProfileScreen(),
  ];

  static const _childTabBodies = <Widget>[
    ChildHomeScreen(),
    ChildTasksScreen(),
    ChildRewardsScreen(),
    ProfileScreen(),
  ];

  void _switchTab(AppTab tab) {
    if (tab == _currentTab) return;
    setState(() => _currentTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final isChild = context.watch<AuthService>().currentUser?.isChild ?? false;
    final tabBodies = isChild ? _childTabBodies : _parentTabBodies;

    return Scaffold(
      appBar: AppBar(title: const Text('Famotive'), centerTitle: true),
      body: SafeArea(
        child: IndexedStack(index: _currentTab.index, children: tabBodies),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab.index,
        onDestinationSelected: (index) => _switchTab(AppTab.values[index]),
        destinations: isChild
            ? const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Tasks'),
                NavigationDestination(icon: Icon(Icons.card_giftcard_outlined), selectedIcon: Icon(Icons.card_giftcard), label: 'Rewards'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
              ]
            : const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Family'),
                NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Progress'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
              ],
      ),
    );
  }
}
