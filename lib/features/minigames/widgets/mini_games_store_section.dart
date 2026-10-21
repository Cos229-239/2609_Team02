import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/mini_game_settings.dart';
import '../../../core/services/mini_game_service.dart';
import '../../../shared/widgets/help_tip.dart';
import '../mini_game_framework.dart';
import '../screens/mini_game_host_screen.dart';

/// Reward Store → "Mini-Games": every game, playable any time just for fun.
/// Casual rounds use the child's own difficulty but never write anything or
/// pay XP/coins (bonus XP only comes from games after an approved task).
class MiniGamesStoreSection extends StatelessWidget {
  const MiniGamesStoreSection({super.key, required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.watch<MiniGameService?>();
    final MiniGameSettings settings = service?.settingsFor(childId) ?? const MiniGameSettings();
    final games = MiniGameRegistry.definitions;
    if (games.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sports_esports, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Mini-Games', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const HelpTip(
              title: 'Mini-Games',
              message: 'Play any game for fun here. After a parent approves a task you may get a bonus round '
                  'that multiplies that task\'s XP!',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Just for fun - practice for your next bonus round!',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: [
            for (final game in games)
              Semantics(
                button: true,
                label: 'Play ${game.id.title}',
                child: InkWell(
                  key: ValueKey('store-game-${game.id.name}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/minigames/casual'),
                    builder: (_) => MiniGameHostScreen(gameId: game.id, casualSettings: settings),
                  )),
                  child: Ink(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: game.id.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: game.id.color.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(game.id.emoji, style: const TextStyle(fontSize: 36)),
                        const SizedBox(height: 6),
                        Text(game.id.title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Expanded(
                          child: Text(
                            game.id.blurb,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.fade,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.play_circle_fill, color: game.id.color, size: 20),
                            const SizedBox(width: 4),
                            Text('Play', style: TextStyle(color: game.id.color, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
