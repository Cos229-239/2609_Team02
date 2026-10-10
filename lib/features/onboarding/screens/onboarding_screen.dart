import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../onboarding_content.dart';
import '../onboarding_controller.dart';

/// Full-screen, swipeable guide: the first-time walkthrough for a parent
/// or child, or one of the topic guides from Settings > App Tour &
/// Tutorials.
///
/// - Back / Next (or swipe) moves between steps; the current step is saved
///   so the guide resumes where it was left (e.g. if the app was closed).
/// - "Skip" closes it without blocking the app; for the first-time
///   walkthrough that counts as done, so it isn't shown again.
/// - The walkthrough ends with "Show me around", which hands off to the
///   spotlight tour in [MainTabShell].
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.guide,
    required this.userId,
    this.resume = true,
  });

  static const routeName = '/onboarding';

  final OnboardingGuide guide;
  final String userId;

  /// Start at the saved step instead of step 1.
  final bool resume;

  /// Pushes the guide as a full-screen dialog.
  static Future<void> open(
    BuildContext context, {
    required OnboardingGuide guide,
    required String userId,
    bool resume = true,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: routeName),
        builder: (_) => OnboardingScreen(guide: guide, userId: userId, resume: resume),
      ),
    );
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  OnboardingController? _controller;
  late int _page;
  late final PageController _pageController;

  List<OnboardingStep> get _steps => widget.guide.steps;
  bool get _isLast => _page == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    _controller = OnboardingController.maybeOf(context);
    _page = widget.resume ? (_controller?.savedStep(widget.userId, widget.guide) ?? 0) : 0;
    _pageController = PageController(initialPage: _page);
    if (!widget.resume) {
      // After the first frame: saving notifies listeners, which mustn't
      // happen while the route is still being built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller?.saveStep(widget.userId, widget.guide.id, 0);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    _controller?.saveStep(widget.userId, widget.guide.id, page);
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _skip() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    if (widget.guide.isWalkthrough) {
      await _controller?.completeWalkthrough(widget.userId, skipped: true);
    }
    if (!mounted) return;
    navigator.pop();
    if (widget.guide.isWalkthrough) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No problem! Replay the tour any time in Settings > App Tour & Tutorials.'),
        ),
      );
    }
  }

  Future<void> _finish({required bool showTour}) async {
    final navigator = Navigator.of(context);
    final controller = _controller;
    if (widget.guide.isWalkthrough) {
      await controller?.completeWalkthrough(widget.userId, skipped: false);
    } else {
      await controller?.markGuideDone(widget.userId, widget.guide.id);
    }
    if (!mounted) return;
    if (showTour && controller != null) {
      controller.requestTour();
      // Back to the tab shell (the root of a signed-in session), which
      // picks up the tour request.
      navigator.popUntil((route) => route.isFirst);
    } else {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _steps.length;
    final canTour = widget.guide.isWalkthrough && _controller != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.guide.title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Step ${_page + 1} of $total',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  // Always present so the header doesn't jump on the last step.
                  Visibility(
                    visible: !_isLast,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: TextButton(
                      key: const Key('onboarding-skip'),
                      onPressed: _isLast ? null : _skip,
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: (_page + 1) / total),
                  duration: const Duration(milliseconds: 280),
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: context.mutedFill,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.secondary),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: total,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _StepPage(step: _steps[index]),
              ),
            ),
            _PageDots(count: total, index: _page, onTap: _goTo),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  if (_page > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('onboarding-back'),
                        onPressed: () => _goTo(_page - 1),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: _isLast
                        ? ElevatedButton.icon(
                            key: Key(canTour ? 'onboarding-tour' : 'onboarding-done'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.secondary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _finish(showTour: canTour),
                            icon: Icon(canTour ? Icons.explore_outlined : Icons.check),
                            label: Text(canTour ? 'Show me around' : 'Done'),
                          )
                        : ElevatedButton(
                            key: const Key('onboarding-next'),
                            onPressed: () => _goTo(_page + 1),
                            child: Text(_page == 0 ? "Let's go" : 'Next'),
                          ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: _isLast && canTour
                  ? TextButton(
                      key: const Key('onboarding-finish'),
                      onPressed: () => _finish(showTour: false),
                      child: const Text('Finish without the tour'),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = step.accent == OnboardingAccent.green;
    final colors = green
        ? const [AppColors.growthGreen, Color(0xFF7CCB7F)]
        : const [AppColors.primaryBlue, Color(0xFF4F8CF7)];

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 36)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.first.withValues(alpha: 0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: step.emoji != null
                    ? Text(step.emoji!, style: const TextStyle(fontSize: 52))
                    : Icon(step.icon, size: 52, color: Colors.white),
              ),
              const SizedBox(height: 28),
              Semantics(
                header: true,
                child: Text(
                  step.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                step.body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.4,
                  color: context.isDarkMode ? Colors.grey.shade300 : Colors.grey.shade800,
                ),
              ),
              if (step.bullets.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  decoration: BoxDecoration(
                    color: colors.first.withValues(alpha: context.isDarkMode ? 0.16 : 0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      for (final bullet in step.bullets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 20,
                                  color: green ? theme.colorScheme.secondary : theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(bullet, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index, required this.onTap});

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: i == index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == index
                          ? theme.colorScheme.primary
                          : (i < index ? theme.colorScheme.secondary.withValues(alpha: 0.6) : context.mutedFill),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
