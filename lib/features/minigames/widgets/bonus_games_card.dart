import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/services/mini_game_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../bonus_game_flow.dart';
import '../mini_game_framework.dart';

/// Child Home: bonus games from approved tasks that are still waiting to be
/// played (e.g. "Maybe later", or the app closed mid-game).
class BonusGamesCard extends StatelessWidget {
  const BonusGamesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MiniGameService?>();
    if (service == null) return const SizedBox.shrink();
    final open = service.openSessions.where((s) => MiniGameRegistry.of(s.gameId) != null).toList();
    if (open.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final next = open.first;

    return AppCard(
      key: const Key('bonus-games-card'),
      color: Colors.amber.withValues(alpha: 0.14),
      onTap: () => openBonusGame(context, next),
      child: Row(
        children: [
          Text(next.gameId.emoji, style: const TextStyle(fontSize: 34)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  open.length == 1 ? 'Bonus game waiting!' : '${open.length} bonus games waiting!',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  'Play ${next.gameId.title} to boost your XP for "${next.taskTitle}".',
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.play_circle_fill, color: AppColors.growthGreen, size: 36),
        ],
      ),
    );
  }
}
