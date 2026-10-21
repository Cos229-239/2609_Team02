import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/models/family_milestone.dart';
import '../../../core/services/milestone_service.dart';
import '../../../shared/widgets/app_card.dart';
import 'milestone_phase_chip.dart';

/// Home-screen entry to the Family Goal board: the goal, its progress
/// ("8 of 20 spaces") and a tap target to open the board. Parents without a
/// goal get a "create one" prompt; children without one see nothing.
class FamilyGoalCard extends StatelessWidget {
  const FamilyGoalCard({super.key, required this.isParent});

  final bool isParent;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MilestoneService?>();
    if (service == null) return const SizedBox.shrink();
    final milestone = service.featured;
    final theme = Theme.of(context);

    if (milestone == null) {
      if (!isParent || !service.loaded) return const SizedBox.shrink();
      return AppCard(
        key: const Key('family-goal-create'),
        color: AppColors.primaryBlue.withValues(alpha: 0.06),
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.milestoneEditor),
        child: Row(
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start a Family Goal', style: theme.textTheme.titleMedium),
                  Text(
                    'Turn chores into a board game toward a shared reward.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      );
    }

    final phase = milestone.phaseAt(DateTime.now());
    return AppCard(
      key: const Key('family-goal-card'),
      color: AppColors.growthGreen.withValues(alpha: 0.08),
      onTap: () => Navigator.of(context).pushNamed(
        milestone.isCompleted ? AppRoutes.milestoneCelebration : AppRoutes.familyBoard,
        arguments: milestone.isCompleted ? milestone.id : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(milestone.illustration, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Family Goal', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                    Text(milestone.title, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (phase != MilestonePhase.active) MilestonePhaseChip(phase: phase, compact: true),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: milestone.progress,
              minHeight: 10,
              color: AppColors.growthGreen,
              backgroundColor: AppColors.growthGreen.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${milestone.position} of ${milestone.boardLength} spaces',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  milestone.isCompleted ? 'Reward unlocked! ${milestone.rewardIcon}' : '${milestone.rewardIcon} ${milestone.rewardTitle}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
