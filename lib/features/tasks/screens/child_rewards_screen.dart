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
            Text('Family Leaderboard', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'See how everyone is doing this week.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < leaderboard.length; i++) ...[
          _LeaderboardRow(rank: i + 1, user: leaderboard[i], isYou: leaderboard[i].id == child.id),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.card_giftcard, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('My Rewards', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Earn XP by completing tasks to unlock these!',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
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

    return AppCard(
      color: isYou ? AppColors.primaryBlue.withValues(alpha: 0.06) : null,
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
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Text(user.avatarEmoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(isYou ? '${user.name} (You)' : user.name, style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: LinearProgressIndicator(value: progress, minHeight: 6),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 16),
              Text('${user.xp} XP', style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}
