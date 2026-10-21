import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/milestone_service.dart';
import '../../../shared/widgets/app_button.dart';

/// "We did it!" - the family reached its goal and the shared reward is
/// unlocked. Parents mark the reward as enjoyed (claimed) once.
class MilestoneCelebrationScreen extends StatefulWidget {
  const MilestoneCelebrationScreen({super.key, required this.milestoneId});

  final String milestoneId;

  @override
  State<MilestoneCelebrationScreen> createState() => _MilestoneCelebrationScreenState();
}

class _MilestoneCelebrationScreenState extends State<MilestoneCelebrationScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _confetti = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat();
  bool _claiming = false;

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    try {
      await context.read<MilestoneService>().claimReward(widget.milestoneId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final milestone = context.watch<MilestoneService>().byId(widget.milestoneId);
    final isParent = context.watch<AuthService>().currentUser?.isParent ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Goal reached!')),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_confetti.value)),
                ),
              ),
            ),
            if (milestone == null)
              const Center(child: Text('This goal is no longer available.'))
            else
              ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 16),
                  Center(child: Text(milestone.rewardIcon, style: const TextStyle(fontSize: 96))),
                  const SizedBox(height: 12),
                  Text(
                    milestone.isCompleted ? 'Your family did it! 🎉' : 'Keep going!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontSize: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    milestone.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.growthGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.growthGreen, width: 2),
                    ),
                    child: Column(
                      children: [
                        Text('Unlocked reward', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          milestone.rewardTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(color: AppColors.growthGreen),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${milestone.boardLength} spaces travelled together',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!milestone.isCompleted)
                    const SizedBox.shrink()
                  else if (milestone.isRewardClaimed)
                    Text(
                      'Enjoyed on ${DateFormat('MMM d').format(milestone.rewardClaimedAt!)} ✅',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    )
                  else if (isParent)
                    AppButton(
                      label: 'We enjoyed our reward!',
                      icon: Icons.check_circle_outline,
                      variant: AppButtonVariant.success,
                      isLoading: _claiming,
                      onPressed: _claim,
                    )
                  else
                    Text(
                      'Ask a parent when you\'ll enjoy it together!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Done',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);

  final double t;
  static const _colors = [Color(0xFF2455C9), Color(0xFF43A047), Color(0xFFFFB300), Color(0xFFE5397D), Color(0xFF7B4FD6)];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (var i = 0; i < 60; i++) {
      final x = rnd.nextDouble() * size.width;
      final speed = 0.5 + rnd.nextDouble();
      final phase = rnd.nextDouble();
      final y = ((t * speed + phase) % 1.0) * (size.height + 40) - 20;
      final sway = math.sin((t * 6 + phase * 10)) * 12;
      final paint = Paint()..color = _colors[i % _colors.length].withValues(alpha: 0.85);
      canvas.save();
      canvas.translate(x + sway, y);
      canvas.rotate(t * 10 + phase * 6);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
