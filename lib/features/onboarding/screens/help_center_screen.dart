import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../onboarding_content.dart';
import '../onboarding_controller.dart';
import 'onboarding_screen.dart';

/// Settings > App Tour & Tutorials: resume or restart the first-time
/// walkthrough, replay the spotlight tour, and open the topic guides.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }
    final controller = OnboardingController.maybeOf(context, listen: true);
    final walkthrough = OnboardingGuides.walkthroughFor(user.role);
    final topics = OnboardingGuides.topicsFor(user.role);

    return Scaffold(
      appBar: AppBar(title: const Text('App Tour & Tutorials')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _WalkthroughCard(user: user, guide: walkthrough, controller: controller),
            const SizedBox(height: 28),
            Text('Guides', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text(
              user.isParent
                  ? 'Short how-tos for setting up and running your household.'
                  : 'Quick refreshers on tasks and rewards.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            for (final guide in topics) ...[
              _GuideTile(user: user, guide: guide, controller: controller),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 20),
            AppCard(
              color: AppColors.growthGreen.withValues(alpha: context.isDarkMode ? 0.14 : 0.07),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tip: tap the ⓘ icons around the app for quick explanations, '
                      'and long-press a tab at the bottom to see what it does.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalkthroughCard extends StatelessWidget {
  const _WalkthroughCard({required this.user, required this.guide, required this.controller});

  final AppUser user;
  final OnboardingGuide guide;
  final OnboardingController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = guide.steps.length;
    final done = controller?.isWalkthroughDone(user.id) ?? false;
    final skipped = controller?.wasWalkthroughSkipped(user.id) ?? false;
    final saved = controller?.savedStep(user.id, guide) ?? 0;
    final inProgress = saved > 0 && !(done && !skipped);

    final String status;
    if (done && !skipped) {
      status = 'Completed ✓';
    } else if (inProgress) {
      status = 'In progress: step ${saved + 1} of $total';
    } else if (skipped) {
      status = 'Skipped - take it whenever you like';
    } else {
      status = 'Not started yet';
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(guide.icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.isParent ? 'Getting started walkthrough' : 'Your welcome tour',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      key: const Key('walkthrough-status'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: done && !skipped ? theme.colorScheme.secondary : Colors.grey.shade600,
                        fontWeight: done && !skipped ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (inProgress) ...[
            AppButton(
              key: const Key('walkthrough-resume'),
              label: 'Resume (step ${saved + 1} of $total)',
              icon: Icons.play_arrow_rounded,
              onPressed: () => OnboardingScreen.open(context, guide: guide, userId: user.id),
            ),
            const SizedBox(height: 10),
          ],
          AppButton(
            key: const Key('walkthrough-restart'),
            label: inProgress
                ? 'Restart from the beginning'
                : (done && !skipped ? 'Replay walkthrough' : 'Start walkthrough'),
            icon: Icons.replay_rounded,
            variant: inProgress ? AppButtonVariant.secondary : AppButtonVariant.primary,
            onPressed: () => OnboardingScreen.open(context, guide: guide, userId: user.id, resume: false),
          ),
          const SizedBox(height: 10),
          AppButton(
            key: const Key('walkthrough-tour'),
            label: 'Show me around the app',
            icon: Icons.explore_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: controller == null
                ? null
                : () {
                    controller!.requestTour();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
          ),
        ],
      ),
    );
  }
}

class _GuideTile extends StatelessWidget {
  const _GuideTile({required this.user, required this.guide, required this.controller});

  final AppUser user;
  final OnboardingGuide guide;
  final OnboardingController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = controller?.isGuideDone(user.id, guide.id) ?? false;
    final saved = controller?.savedStep(user.id, guide) ?? 0;

    final Widget trailing;
    if (saved > 0) {
      trailing = Text(
        '${saved + 1}/${guide.steps.length}',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
      );
    } else if (done) {
      trailing = Icon(Icons.check_circle, color: theme.colorScheme.secondary, size: 20);
    } else {
      trailing = const SizedBox.shrink();
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => OnboardingScreen.open(context, guide: guide, userId: user.id),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.14),
            child: Icon(guide.icon, size: 20, color: theme.colorScheme.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(guide.title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  guide.summary,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          trailing,
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}
