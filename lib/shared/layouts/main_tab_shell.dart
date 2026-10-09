import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/user.dart';
import '../../core/services/auth_service.dart';
import '../../features/household/screens/family_screen.dart';
import '../../features/household/screens/no_household_screen.dart';
import '../../features/household/widgets/household_switcher.dart';
import '../../features/onboarding/onboarding_content.dart';
import '../../features/onboarding/onboarding_controller.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/household/screens/household_home_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/rewards/screens/progress_screen.dart';
import '../../features/tasks/screens/child_home_screen.dart';
import '../../features/tasks/screens/child_rewards_screen.dart';
import '../../features/tasks/screens/child_tasks_screen.dart';
import '../widgets/coach_mark_tour.dart';

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

  // ---------------------------------------------------------------------
  // Onboarding: auto-start the first-time walkthrough, and run the
  // spotlight ("Show me around") tour when it's requested.
  // ---------------------------------------------------------------------

  /// One key per element the spotlight tour can point at, handed down to
  /// the tab screens through [CoachMarkScope]. Owned by this State (not
  /// static) so two shells briefly on screen together can't clash.
  final Map<CoachTarget, GlobalKey> _coachKeys = {
    for (final target in CoachTarget.values) target: GlobalKey(debugLabel: 'coach-${target.name}'),
  };

  OnboardingController? _onboarding;

  /// User id the auto-start check already ran for, so it runs once per
  /// session per user (not on every rebuild).
  String? _autoStartCheckedFor;
  bool _tourRunning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = OnboardingController.maybeOf(context);
    if (!identical(controller, _onboarding)) {
      _onboarding?.removeListener(_onOnboardingChanged);
      _onboarding = controller;
      controller?.addListener(_onOnboardingChanged);
    }
  }

  @override
  void dispose() {
    _onboarding?.removeListener(_onOnboardingChanged);
    super.dispose();
  }

  void _onOnboardingChanged() {
    final controller = _onboarding;
    if (controller == null || !mounted) return;
    if (controller.consumeTourRequest()) {
      // Let the walkthrough/help route finish popping first.
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _startTour();
      });
    }
    // Saved progress may finish loading after the first build.
    _scheduleAutoStartCheck();
  }

  bool _autoStartScheduled = false;

  /// Safe to call from build: the actual check runs after the frame.
  void _scheduleAutoStartCheck() {
    if (_autoStartScheduled) return;
    _autoStartScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartScheduled = false;
      _maybeAutoStartWalkthrough();
    });
  }

  void _maybeAutoStartWalkthrough() {
    if (!mounted) return;
    final controller = _onboarding;
    final user = context.read<AuthService>().currentUser;
    // Wait until the user is in a household (the tabs exist) and their
    // saved progress has loaded.
    if (controller == null || !controller.isLoaded) return;
    if (user == null || user.householdId == null) return;
    if (_autoStartCheckedFor == user.id) return;
    _autoStartCheckedFor = user.id;

    if (!controller.shouldAutoStart(user)) return;
    // Don't cover something the user opened on top of the tabs.
    if (ModalRoute.of(context)?.isCurrent == false) return;

    OnboardingScreen.open(
      context,
      guide: OnboardingGuides.walkthroughFor(user.role),
      userId: user.id,
    );
  }

  Future<void> _startTour() async {
    if (_tourRunning || !mounted) return;
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.householdId == null) return;

    _tourRunning = true;
    setState(() => _currentTab = AppTab.home);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      _tourRunning = false;
      return;
    }
    await CoachMarkTour.show(context, _tourFor(user.role));
    _tourRunning = false;
  }

  List<CoachMark> _tourFor(UserRole role) {
    final nav = _coachKeys[CoachTarget.navigationBar];
    const navCount = 4;
    CoachMark navMark(int index, String title, String body, IconData icon) => CoachMark(
          targetKey: nav,
          navIndex: index,
          navCount: navCount,
          title: title,
          body: body,
          icon: icon,
        );

    if (role == UserRole.child) {
      return [
        CoachMark(
          targetKey: _coachKeys[CoachTarget.childProgress],
          title: 'Your progress',
          body: "See how many of today's tasks you've finished and the XP waiting for you.",
          icon: Icons.star_outline,
        ),
        navMark(1, 'Tasks', 'Claim new tasks, mark them complete, and see what you\'ve finished.',
            Icons.assignment_turned_in_outlined),
        navMark(2, 'Rewards', 'Check the leaderboard and spend your coins in the Reward Store.', Icons.redeem_outlined),
        navMark(3, 'Settings', 'Turn on dark mode or replay this tour any time from App Tour & Tutorials.',
            Icons.settings_outlined),
      ];
    }
    return [
      CoachMark(
        targetKey: _coachKeys[CoachTarget.householdSwitcher],
        title: 'Your household',
        body: 'Tap the household name to switch between households or manage them.',
        icon: Icons.home_work_outlined,
      ),
      CoachMark(
        targetKey: _coachKeys[CoachTarget.createTask],
        title: 'Create a task',
        body: 'Start here: name a chore, set XP and coins, a due date or a repeat, and assign it.',
        icon: Icons.add_task,
      ),
      navMark(1, 'Family', 'Add children, invite another parent, and stock the reward store.', Icons.groups_outlined),
      navMark(2, 'Progress', 'Every task in the household, plus each child\'s XP and coins.', Icons.bar_chart_outlined),
      navMark(3, 'Settings', 'Turn on dark mode or replay this tour any time from App Tour & Tutorials.',
          Icons.settings_outlined),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthService>().currentUser;
    final isChild = currentUser?.isChild ?? false;
    final tabBodies = isChild ? _childTabBodies : _parentTabBodies;
    if (currentUser != null && currentUser.id != _autoStartCheckedFor) {
      _scheduleAutoStartCheck();
    }

    // Not in any household yet (e.g. waiting for the admin to approve a
    // join request): no tabs, just the "join / waiting" screen.
    if (currentUser != null && currentUser.householdId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Famotive', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: const SafeArea(child: NoHouseholdScreen()),
      );
    }

    return CoachMarkScope(
      keys: _coachKeys,
      child: Scaffold(
      // This shell is always the root of a signed-in session (see
      // FamotiveApp.onGenerateInitialRoutes) and its 4 tabs are switched
      // via IndexedStack, not the Navigator — so there's never a
      // legitimate 'back' destination from here. Force the leading back
      // arrow off rather than relying on canPop(), so it can't reappear
      // if this shell is ever reached with something still under it on
      // the stack.
      appBar: AppBar(
        // Active household's name; tap to switch households.
        title: KeyedSubtree(
          key: _coachKeys[CoachTarget.householdSwitcher],
          child: const HouseholdSwitcher(),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),

      body: SafeArea(
        child: IndexedStack(index: _currentTab.index, children: tabBodies),
      ),
      bottomNavigationBar: NavigationBar(
        key: _coachKeys[CoachTarget.navigationBar],
        selectedIndex: _currentTab.index,
        onDestinationSelected: (index) => _switchTab(AppTab.values[index]),
        destinations: isChild
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                  tooltip: 'Home: today at a glance',
                ),
                NavigationDestination(
                  icon: Icon(Icons.assignment_turned_in_outlined),
                  selectedIcon: Icon(Icons.assignment_turned_in),
                  label: 'Tasks',
                  tooltip: "Tasks: claim, complete and review your tasks",
                ),
                NavigationDestination(
                  icon: Icon(Icons.redeem_outlined),
                  selectedIcon: Icon(Icons.redeem),
                  label: 'Rewards',
                  tooltip: "Rewards: leaderboard and reward store",
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                  tooltip: 'Settings: account, dark mode, app tour and help',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                  tooltip: 'Home: today at a glance',
                ),
                NavigationDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups),
                  label: 'Family',
                  tooltip: "Family: members, invites and reward store",
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'Progress',
                  tooltip: "Progress: every task and each child's totals",
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                  tooltip: 'Settings: account, dark mode, app tour and help',
                ),
              ],
      ),
      ),
    );
  }
}
