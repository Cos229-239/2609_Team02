import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../shared/widgets/app_card.dart';

/// Child Home: the door into Rex's Room (the pet game).
class RexRoomCard extends StatelessWidget {
  const RexRoomCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      key: const Key('rex-room-card'),
      color: const Color(0xFF3FAE3A).withValues(alpha: 0.14),
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.rexRoom),
      child: Row(
        children: [
          const Text('🦖', style: TextStyle(fontSize: 38)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Visit Rex', style: theme.textTheme.titleMedium),
                Text(
                  'Finish tasks to keep your dino happy and healthy!',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
