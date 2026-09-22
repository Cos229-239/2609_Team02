import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/redemption.dart';
import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../rewards/widgets/reward_progress_tile.dart';
import '../../../core/models/reward.dart';

/// "Rewards" tab for a signed-in child: the reward store, the family
/// leaderboard, and a personal redemption history.
///
/// This only returns the tab's content; [MainTabShell] supplies the
/// shared app bar, bottom nav bar and [SafeArea].
class ChildRewardsScreen extends StatelessWidget {
  const ChildRewardsScreen({super.key});

  Future<void> _redeem(BuildContext context, DatabaseService db, AppUser child, String rewardId, String rewardTitle) async {
    try {
      await db.redeemReward(rewardId: rewardId, childId: child.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🎉 "$rewardTitle" redeemed! A parent will see it in Family.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final db = context.watch<DatabaseService>();
    final authChild = auth.currentUser;

    if (authChild == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // AuthService.currentUser is a login-time snapshot, not live:
    // read coins/pinnedRewardId from the live-synced member list instead.
    final child = db.userById(authChild.id) ?? authChild;

    final leaderboard = [...db.children]..sort((a, b) => b.xp.compareTo(a.xp));
    final history = db.redemptionsForChild(child.id);
    final pinnedReward = child.pinnedRewardId == null ? null : db.rewardById(child.pinnedRewardId!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pinnedReward != null) ...[
          _PinnedGoalCard(
            reward: pinnedReward,
            childCoins: child.coins,
            onUnpin: () => db.setPinnedReward(child.id, null),
          ),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            Text('Family Leaderboard', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'See how everyone is doing this week.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < leaderboard.length; i++) ...[
          _LeaderboardRow(rank: i + 1, user: leaderboard[i], isYou: leaderboard[i].id == child.id),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 24),
        AppCard(
          color: AppColors.growthGreen.withValues(alpha: 0.08),
          child: Row(
            children: [
              Icon(Icons.monetization_on, color: Colors.amber.shade700, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Coin Balance', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700)),
                    Text('${child.coins} coins', style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.storefront, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Reward Store', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Earn coins by completing tasks, then redeem them here!',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        if (db.availableRewards.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No rewards in the store yet - ask a parent to add some!'),
          )
        else
          for (final reward in db.availableRewards) ...[
            RewardProgressTile(
              reward: reward,
              childCoins: child.coins,
              onRedeem: () => _redeem(context, db, child, reward.id, reward.title),
              isPinned: child.pinnedRewardId == reward.id,
              onTogglePin: () => db.setPinnedReward(
                child.id,
                child.pinnedRewardId == reward.id ? null : reward.id,
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('My Redemption History', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Everything you\'ve redeemed from the store so far.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Nothing redeemed yet.'),
          )
        else
          for (final redemption in history) ...[
            _RedemptionRow(redemption: redemption),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _RedemptionRow extends StatelessWidget {
  const _RedemptionRow({required this.redemption});

  final Redemption redemption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = DateFormat('MMM d, yyyy • h:mm a').format(redemption.redeemedAt);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Text(redemption.rewardIcon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(redemption.rewardTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(formatted, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monetization_on, size: 16, color: Colors.amber.shade700),
              const SizedBox(width: 2),
              Text('-${redemption.coinCost}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.rank, required this.user, required this.isYou});

  final int rank;
  final AppUser user;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (user.xp / AppConstants.levelUpXpThreshold).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '#$rank',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 10),
          Text(
  user.avatarEmoji,
  style: const TextStyle(fontSize: 28),
),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(isYou ? '${user.name} (You)' : user.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: LinearProgressIndicator(
  value: progress,
  minHeight: 7,
  color: AppColors.growthGreen,
  backgroundColor: AppColors.growthGreen.withValues(alpha: 0.15),
),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(
  Icons.star,
  color: AppColors.growthGreen,
  size: 18,
),
const SizedBox(height: 2),
              Text('${user.xp} XP', style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.growthGreen,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              )),
            ],
          ),
        ],
      ),
    );
  }
}


class _PinnedGoalCard extends StatelessWidget {
  const _PinnedGoalCard({
    required this.reward,
    required this.childCoins,
    this.onUnpin,
  });

  final Reward reward;
  final int childCoins;
  final VoidCallback? onUnpin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (childCoins / (reward.coinCost == 0 ? 1 : reward.coinCost)).clamp(0.0, 1.0).toDouble();
    final coinsLeft = (reward.coinCost - childCoins).clamp(0, reward.coinCost);
    final achieved = childCoins >= reward.coinCost;

    return AppCard(
      color: Colors.amber.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin, color: Colors.amber.shade700, size: 18),
              const SizedBox(width: 6),
              Text(
                'Your Goal',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (onUnpin != null)
                IconButton(
                  onPressed: onUnpin,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Unpin goal',
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reward.icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward.title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 7,
                        color: Colors.amber.shade700,
                        backgroundColor: Colors.amber.withValues(alpha: 0.15),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      achieved
                          ? 'Ready to claim! 🎉'
                          : '$coinsLeft of ${reward.coinCost} coins to go',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
