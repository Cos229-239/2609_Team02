import 'package:flutter/material.dart';

import '../../../core/models/reward.dart';
import '../../../app/theme.dart';

/// One reward row: its price, an optional pin toggle, and either a
/// "Claim Now" button or how many coins are still needed.
class RewardProgressTile extends StatelessWidget {
  const RewardProgressTile({
    super.key,
    required this.reward,
    required this.childCoins,
    this.onRedeem,
    this.isPinned = false,
    this.onTogglePin,
  });

  final Reward reward;
  final int childCoins;

  /// Null hides the claim action (e.g. read-only previews).
  final VoidCallback? onRedeem;

  /// Whether this reward is the child's currently pinned goal.
  final bool isPinned;

  /// Null hides the pin action.
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final unlocked = childCoins >= reward.coinCost;
    final coinsLeft = (reward.coinCost - childCoins).clamp(0, reward.coinCost);

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
                Row(
                  children: [
                    Icon(Icons.monetization_on, size: 15, color: Colors.amber.shade700),
                    const SizedBox(width: 3),
                    Text(
                      '${reward.coinCost} coins',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.growthGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTogglePin != null)
            IconButton(
              onPressed: onTogglePin,
              visualDensity: VisualDensity.compact,
              tooltip: isPinned ? 'Unpin goal' : 'Pin as goal',
              icon: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: isPinned ? Colors.amber.shade700 : Colors.grey.shade400,
                size: 20,
              ),
            ),
          const SizedBox(width: 6),
          if (unlocked && onRedeem != null)
            ElevatedButton(
              onPressed: onRedeem,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Claim Now'),
            )
          else if (unlocked)
            const Icon(Icons.lock_open, color: AppColors.growthGreen, size: 22)
          else
            Text(
              '$coinsLeft left',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
