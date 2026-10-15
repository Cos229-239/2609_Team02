import 'package:flutter/material.dart';

import '../core/models/user.dart';
import '../features/onboarding/onboarding_content.dart';

/// The two first-time walkthroughs being A/B tested.
///
/// - **A (verbose)** is whatever `dev` currently ships: read live from
///   [OnboardingGuides], so it always matches the real app.
/// - **B (minimal)** is a snapshot of the four-screen walkthrough from
///   `feature/tutorial-final` (commit d46b855). It's copied here rather
///   than imported so both variants can run side by side in one build; if
///   that branch changes, update this file to match.
enum WalkthroughVariant {
  a('A', 'Verbose (dev)'),
  b('B', 'Minimal (feature/tutorial-final)');

  const WalkthroughVariant(this.code, this.label);

  final String code;
  final String label;

  static WalkthroughVariant? parse(String? value) => switch (value?.toUpperCase()) {
        'A' => WalkthroughVariant.a,
        'B' => WalkthroughVariant.b,
        _ => null,
      };

  OnboardingGuide guideFor(UserRole role) => switch (this) {
        WalkthroughVariant.a => OnboardingGuides.walkthroughFor(role),
        WalkthroughVariant.b => role == UserRole.parent ? MinimalWalkthrough.parent : MinimalWalkthrough.child,
      };
}

class MinimalWalkthrough {
  MinimalWalkthrough._();

  static const parent = OnboardingGuide(
    id: OnboardingGuideId.parentWalkthrough,
    title: 'Welcome to Famotive',
    summary: 'A quick tour of households, tasks and rewards.',
    icon: Icons.waving_hand_outlined,
    steps: [
      OnboardingStep(
        title: 'Welcome to Famotive!',
        body: 'Where everyday chores become exciting quests! '
            'Complete tasks, earn rewards, and make family teamwork more fun.',
        icon: Icons.waving_hand_outlined,
        bullets: [
          'You assign a task',
          'Your child completes it',
          'You approve it, and they earn rewards',
        ],
      ),
      OnboardingStep(
        title: 'Create a task',
        body: 'Tap "Create a New Task" on Home. Give it an icon and a clear '
            'name - kids should know exactly what "done" looks like.',
        icon: Icons.add_task,
        bullets: [
          'Set the amount of XP and coins it earns',
          'With Premium, turn on Photo Proof to see the result',
          '"Suggest" writes a description for you, on-device',
        ],
      ),
      OnboardingStep(
        title: 'Stock the reward store',
        body: 'Rewards are what kids spend their coins on. Add them from the '
            'Family tab.',
        icon: Icons.storefront_outlined,
        accent: OnboardingAccent.blue,
        bullets: [
          'Tap "Add Reward" and set a coin price',
          'You\'re notified when a reward is redeemed',
          'XP is never spent - it powers levels and the leaderboard',
        ],
      ),
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

  static const child = OnboardingGuide(
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
      OnboardingStep(
        title: 'Find your quests',
        body: 'Home shows today\'s tasks. The Tasks tab has everything else.',
        icon: Icons.assignment_turned_in_outlined,
        emoji: '🗺️',
        bullets: [
          'Tasks a parent gave you are already yours',
          'Claim "Available Tasks" to make them yours',
          'Tip: swipe a task right to claim it',
        ],
      ),
      OnboardingStep(
        title: 'Spend your coins',
        body: 'Open the Rewards tab to see the Reward Store your family set up.',
        icon: Icons.redeem_outlined,
        emoji: '🎁',
        accent: OnboardingAccent.blue,
        bullets: [
          'Redeem a reward when you have enough coins',
          'Pin one as your goal to track your progress',
          'Your parent gets told so they can hand it over',
        ],
      ),
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
}
