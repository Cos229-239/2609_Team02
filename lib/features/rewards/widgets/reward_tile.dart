import 'package:flutter/material.dart';

import '../../../core/models/reward.dart';
import '../../../shared/widgets/app_card.dart';

/// One selectable reward row (radio-style), used on the "choose rewards"
/// screen where a parent picks a reward task for a child to work toward.
///
/// Expects a `RadioGroup<String>` ancestor (see [RewardChooseScreen]) to
/// supply the shared selection value/callback to its [Radio].
class RewardTile extends StatelessWidget {
  const RewardTile({
    super.key,
    required this.reward,
    required this.selected,
    required this.onTap,
  });

  final Reward reward;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.06) : null,
      child: Row(
        children: [
          Text(reward.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reward.title, style: theme.textTheme.titleMedium),
                Text(
                  reward.description,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Radio<String>(value: reward.id),
        ],
      ),
    );
  }
}
