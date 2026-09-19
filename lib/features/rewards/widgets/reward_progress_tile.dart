import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/reward.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../app/theme.dart';

/// One reward from the catalog, shown with a progress bar toward its XP
/// cost. Used on the child's Rewards tab so kids can see what they're
/// working toward alongside the family leaderboard.
class RewardProgressTile extends StatelessWidget {
  const RewardProgressTile({super.key, required this.reward, required this.childXp});

  final Reward reward;
  final int childXp;

  @override
  Widget build(BuildContext context) {
    final progress = (childXp / (reward.xpCost == 0 ? 1 : reward.xpCost)).clamp(0.0, 1.0).toDouble();
    final unlocked = reward.xpCost > 0 && childXp >= reward.xpCost;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          Text(reward.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reward.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                )),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress, minHeight: 6, color: AppColors.growthGreen, backgroundColor: AppColors.growthGreen.withValues(alpha: 0.12)),
                ),
                const SizedBox(height: 6),
                Text(
                  '$childXp / ${reward.xpCost} XP',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.growthGreen, 
                  fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (unlocked)
            const Icon(Icons.lock_open, color: AppColors.growthGreen, size: 22)
          else
          Icon(Icons.lock_outline, color: AppColors.growthGreen.withValues(alpha: 0.55), size: 22), 
        ],
      ),
    );
  }
}
