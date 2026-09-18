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

    return AppCard(
      child: Row(
        children: [
          Text(reward.icon, style: const TextStyle(fontSize: AppConstants.emojiIconLg)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reward.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: progress, minHeight: 6),
                ),
                const SizedBox(height: 2),
                Text(
                  '$childXp / ${reward.xpCost} XP',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (unlocked)
            const Icon(Icons.lock_open, color: AppColors.growthGreen)
          else
            const Icon(Icons.lock_outline, color: Colors.grey),
        ],
      ),
    );
  }
}
