import 'package:flutter/material.dart';

import '../../core/models/user.dart';

/// Every guide the app can show. The two `*Walkthrough` guides are the
/// first-time, role-specific introductions; the rest are topic guides that
/// can be opened any time from Settings > App Tour & Tutorials.
enum OnboardingGuideId {
  parentWalkthrough,
  childWalkthrough,
  taskCreation,
  household,
  parentRewards,
  childTasks,
  childRewards,
}

/// One page of a guide. Kept short on purpose: a title, one or two
/// sentences, and up to ~4 scannable bullets so it fits a phone screen.
class OnboardingStep {
  const OnboardingStep({
    required this.title,
    required this.body,
    required this.icon,
    this.emoji,
    this.bullets = const [],
    this.accent = OnboardingAccent.blue,
  });

  final String title;
  final String body;
  final IconData icon;

  /// Shown instead of [icon] when set (the kid-facing guides use emoji).
  final String? emoji;
  final List<String> bullets;
  final OnboardingAccent accent;
}

/// Famotive's two brand accents: blue for "how things work / navigation",
/// green for growth and reward moments.
enum OnboardingAccent { blue, green }

class OnboardingGuide {
  const OnboardingGuide({
    required this.id,
    required this.title,
    required this.summary,
    required this.icon,
    required this.steps,
  });

  final OnboardingGuideId id;
  final String title;
  final String summary;
  final IconData icon;
  final List<OnboardingStep> steps;

  bool get isWalkthrough =>
      id == OnboardingGuideId.parentWalkthrough || id == OnboardingGuideId.childWalkthrough;
}

class OnboardingGuides {
  OnboardingGuides._();

  /// The first-time walkthrough for [role].
  static OnboardingGuide walkthroughFor(UserRole role) =>
      role == UserRole.parent ? parentWalkthrough : childWalkthrough;

  /// Topic guides listed in the Help screen for [role].
  static List<OnboardingGuide> topicsFor(UserRole role) => role == UserRole.parent
      ? const [taskCreation, household, parentRewards]
      : const [childTasks, childRewards];

  static OnboardingGuide byId(OnboardingGuideId id) => switch (id) {
        OnboardingGuideId.parentWalkthrough => parentWalkthrough,
        OnboardingGuideId.childWalkthrough => childWalkthrough,
        OnboardingGuideId.taskCreation => taskCreation,
        OnboardingGuideId.household => household,
        OnboardingGuideId.parentRewards => parentRewards,
        OnboardingGuideId.childTasks => childTasks,
        OnboardingGuideId.childRewards => childRewards,
      };

  // ---------------------------------------------------------------------
  // Steps shared between the walkthroughs and the topic guides.
  // ---------------------------------------------------------------------

  static const _householdStep = OnboardingStep(
    title: 'Your household',
    body: 'Everything in Famotive lives inside a household: your family\'s '
        'members, tasks and reward store.',
    icon: Icons.home_work_outlined,
    bullets: [
      'Create a household, or join one with its invite code',
      'Tap the household name at the top to switch households',
      'Admins can rename it with the ✏️ on the Family tab',
      'Manage households in Settings > Households',
    ],
  );

  static const _inviteStep = OnboardingStep(
    title: 'Bring in your family',
    body: 'Use the Family tab to add the people you share chores with.',
    icon: Icons.group_add_outlined,
    bullets: [
      'Add Child creates a login for a kid - no email needed',
      'Invite shares your code with another parent or an older child',
      'As admin, you approve anyone who asks to join',
      'Use the ⋮ menu on a member to manage them',
    ],
  );

  static const _createTaskStep = OnboardingStep(
    title: 'Create a task',
    body: 'Tap "Create a New Task" on Home. Give it an icon and a clear '
        'name - kids should know exactly what "done" looks like.',
    icon: Icons.add_task,
    bullets: [
      'Set the XP and coins it earns',
      'With Premium, turn on Photo Proof to see the result',
      '"Suggest" writes a description for you, on-device',
    ],
  );

  static const _scheduleStep = OnboardingStep(
    title: 'Due dates & repeating chores',
    body: 'Pick a due date, or make it repeat so you only set it up once.',
    icon: Icons.event_repeat,
    bullets: [
      'Repeat daily, weekly, or on the days you choose',
      'Each day\'s copy shows up that morning',
      'Edit or stop a repeating task from "Repeating Tasks" on Home',
    ],
  );

  static const _assignStep = OnboardingStep(
    title: 'Assign it',
    body: 'Choose who the task is for under "Assign To".',
    icon: Icons.assignment_ind_outlined,
    bullets: [
      'Pick a child to give it straight to them',
      'Or choose Household Task so any child can claim it',
      'Re-assign later from the Progress tab',
    ],
  );

  static const _approveStep = OnboardingStep(
    title: 'Approve & reward',
    body: 'When a child finishes, the task lands in "Needs Approval" on '
        'your Home screen.',
    icon: Icons.verified_outlined,
    accent: OnboardingAccent.green,
    bullets: [
      'Swipe right to approve - XP and coins are paid out',
      'Swipe left to delete it',
      'Check the photo first if proof was required',
    ],
  );

  static const _rewardStoreStep = OnboardingStep(
    title: 'Stock the reward store',
    body: 'Rewards are what kids spend their coins on. Add them from the '
        'Family tab.',
    icon: Icons.storefront_outlined,
    accent: OnboardingAccent.green,
    bullets: [
      'Tap "Add Reward" and set a coin price',
      'You\'re notified when a reward is redeemed',
      'XP is never spent - it powers levels and the leaderboard',
    ],
  );

  static const _progressStep = OnboardingStep(
    title: 'Track progress',
    body: 'The Progress tab shows every task in the household and how '
        'each child is doing.',
    icon: Icons.bar_chart_rounded,
    accent: OnboardingAccent.green,
    bullets: [
      'See each child\'s XP and coins at a glance',
      'Approve, re-assign or duplicate tasks from there',
    ],
  );

  // ---------------------------------------------------------------------
  // First-time walkthroughs
  // ---------------------------------------------------------------------

  static const parentWalkthrough = OnboardingGuide(
    id: OnboardingGuideId.parentWalkthrough,
    title: 'Welcome to Famotive',
    summary: 'A quick tour of households, tasks and rewards.',
    icon: Icons.waving_hand_outlined,
    steps: [
      OnboardingStep(
        title: 'Welcome to Famotive!',
        body: 'Famotive turns chores into quests: kids earn XP and coins, and '
            'you get one place to organize the household.',
        icon: Icons.waving_hand_outlined,
        bullets: [
          'You assign a task',
          'Your child completes it',
          'You approve it, and they earn rewards',
        ],
      ),
      _householdStep,
      _inviteStep,
      _createTaskStep,
      _scheduleStep,
      _assignStep,
      _approveStep,
      _rewardStoreStep,
      _progressStep,
      OnboardingStep(
        title: 'You\'re all set!',
        body: 'Tap "Show me around" for a quick look at where everything is. '
            'You can replay this any time from Settings > App Tour & Tutorials.',
        icon: Icons.celebration_outlined,
        accent: OnboardingAccent.green,
        bullets: [
          'Look for the ⓘ icons for quick tips',
          'Long-press the tabs to see what they do',
        ],
      ),
    ],
  );

  static const childWalkthrough = OnboardingGuide(
    id: OnboardingGuideId.childWalkthrough,
    title: 'Welcome, hero!',
    summary: 'How quests, XP, coins and rewards work.',
    icon: Icons.rocket_launch_outlined,
    steps: [
      OnboardingStep(
        title: 'Welcome, hero!',
        body: 'In Famotive your chores are quests. Finish them to earn XP '
            'and coins, then spend coins on real rewards.',
        icon: Icons.rocket_launch_outlined,
        emoji: '🦸',
      ),
      _childTasksStep,
      _childCompleteStep,
      _childXpStep,
      _childRewardsStep,
      _childLeaderboardStep,
      OnboardingStep(
        title: 'Ready for your first quest?',
        body: 'Tap "Show me around" to see where everything is. You can '
            'watch this again in Settings > App Tour & Tutorials.',
        icon: Icons.flag_outlined,
        emoji: '🚀',
        accent: OnboardingAccent.green,
      ),
    ],
  );

  static const _childTasksStep = OnboardingStep(
    title: 'Find your quests',
    body: 'Home shows today\'s tasks. The Tasks tab has everything else.',
    icon: Icons.assignment_turned_in_outlined,
    emoji: '🗺️',
    bullets: [
      'Tasks a parent gave you are already yours',
      'Claim "Available Tasks" to make them yours',
      'Tip: swipe a task right to claim it',
    ],
  );

  static const _childCompleteStep = OnboardingStep(
    title: 'Finish the job',
    body: 'Done? Tap Complete (or swipe right). Some tasks ask for a photo '
        'to show your work.',
    icon: Icons.check_circle_outline,
    emoji: '✅',
    bullets: [
      'It moves to "Awaiting Approval"',
      'A parent checks it and approves it',
      'Then your rewards are added!',
    ],
  );

  static const _childXpStep = OnboardingStep(
    title: 'XP and coins',
    body: 'Every approved task pays out two things.',
    icon: Icons.star_outline,
    emoji: '⭐',
    accent: OnboardingAccent.green,
    bullets: [
      'XP ⭐ shows how far you\'ve come - you keep it forever',
      'Coins 🪙 are money you can spend on rewards',
      'Bigger tasks usually earn more of both',
    ],
  );

  static const _childRewardsStep = OnboardingStep(
    title: 'Spend your coins',
    body: 'Open the Rewards tab to see the Reward Store your family set up.',
    icon: Icons.redeem_outlined,
    emoji: '🎁',
    accent: OnboardingAccent.green,
    bullets: [
      'Redeem a reward when you have enough coins',
      'Pin one as your goal to track your progress',
      'Your parent gets told so they can hand it over',
    ],
  );

  static const _childLeaderboardStep = OnboardingStep(
    title: 'Climb the leaderboard',
    body: 'The Family Leaderboard on the Rewards tab ranks everyone by XP.',
    icon: Icons.emoji_events_outlined,
    emoji: '🏆',
    accent: OnboardingAccent.green,
    bullets: [
      'Check Home to see how many tasks are left today',
      'The Completed view shows everything you\'ve finished',
    ],
  );

  // ---------------------------------------------------------------------
  // Topic guides (Settings > App Tour & Tutorials)
  // ---------------------------------------------------------------------

  static const taskCreation = OnboardingGuide(
    id: OnboardingGuideId.taskCreation,
    title: 'Creating tasks',
    summary: 'Due dates, assigning and repeating chores.',
    icon: Icons.add_task,
    steps: [_createTaskStep, _scheduleStep, _assignStep, _approveStep],
  );

  static const household = OnboardingGuide(
    id: OnboardingGuideId.household,
    title: 'Managing your household',
    summary: 'Create or join, invite members, profiles and settings.',
    icon: Icons.home_work_outlined,
    steps: [
      _householdStep,
      _inviteStep,
      OnboardingStep(
        title: 'Profiles & settings',
        body: 'Everyone has their own profile and avatar.',
        icon: Icons.manage_accounts_outlined,
        bullets: [
          'Settings > Account Settings: name, avatar, email, password',
          'Settings > Notifications: choose what you\'re told about',
          'Settings > Households: switch, create, join or leave',
        ],
      ),
    ],
  );

  static const parentRewards = OnboardingGuide(
    id: OnboardingGuideId.parentRewards,
    title: 'Rewards & XP',
    summary: 'How kids earn XP and coins, and redeem rewards.',
    icon: Icons.redeem_outlined,
    steps: [
      OnboardingStep(
        title: 'XP vs. coins',
        body: 'Each task pays out the XP and coins you set when creating it.',
        icon: Icons.star_outline,
        accent: OnboardingAccent.green,
        bullets: [
          'XP is never spent: it drives levels and the leaderboard',
          'Coins are spendable in the reward store',
          'Both are paid when you approve the task',
        ],
      ),
      _rewardStoreStep,
      _progressStep,
    ],
  );

  static const childTasks = OnboardingGuide(
    id: OnboardingGuideId.childTasks,
    title: 'Doing tasks',
    summary: 'Claiming, completing and getting approved.',
    icon: Icons.assignment_turned_in_outlined,
    steps: [_childTasksStep, _childCompleteStep],
  );

  static const childRewards = OnboardingGuide(
    id: OnboardingGuideId.childRewards,
    title: 'XP, coins & rewards',
    summary: 'What you earn and how to spend it.',
    icon: Icons.redeem_outlined,
    steps: [_childXpStep, _childRewardsStep, _childLeaderboardStep],
  );
}
