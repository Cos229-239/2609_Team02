import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../rewards/widgets/reward_progress_tile.dart';

/// "Rewards" tab for a signed-in child — where the reward catalog and the
/// whole-family leaderboard live now that the Tasks tab's second view was
/// repurposed into a personal task history log.
///
/// This only returns the tab's content; [MainTabShell] supplies the
/// shared app bar, bottom nav bar and [SafeArea].
class ChildRewardsScreen extends StatelessWidget {
  const ChildRewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final db = context.watch<DatabaseService>();
    final child = auth.currentUser;

    if (child == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final leaderboard = [...db.children]..sort((a, b) => b.xp.compareTo(a.xp));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        Row(
          children: [
            Icon(Icons.card_giftcard, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('My Rewards', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Earn XP by completing tasks to unlock these!',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        for (final reward in db.availableRewards) ...[
          RewardProgressTile(reward: reward, childXp: child.xp),
          const SizedBox(height: 8),
        ],
      ],
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
