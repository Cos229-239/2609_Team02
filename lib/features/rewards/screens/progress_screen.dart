import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';

/// "Progress" tab — family-wide progress toward goals/levels. Placeholder
/// visualization built from each child's XP total.
///
/// This only returns the tab's content; `MainTabShell` supplies the
/// shared app bar, bottom nav bar and `SafeArea`.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final children = db.children;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Family Progress', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'See how everyone is doing this week.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        for (final child in children) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(child.avatarEmoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Text(child.name, style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Text('${child.xp} XP'),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: LinearProgressIndicator(
                    value: (child.xp / AppConstants.levelUpXpThreshold).clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${AppConstants.levelUpXpThreshold - child.xp > 0 ? AppConstants.levelUpXpThreshold - child.xp : 0} XP to next level',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
