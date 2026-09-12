import 'package:flutter/material.dart';

import '../../../core/models/user.dart';
import '../../../shared/widgets/app_card.dart';

/// Reusable row showing one family member's avatar, name/role and XP —
/// used on both the household home screen and the family screen.
class FamilyMemberCard extends StatelessWidget {
  const FamilyMemberCard({super.key, required this.user, this.onTap});

  final AppUser user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Text(user.avatarEmoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: theme.textTheme.titleMedium),
                Text(
                  user.isParent ? 'Parent' : 'Age ${user.age ?? '—'}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (user.isChild)
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text('${user.xp} XP', style: theme.textTheme.titleMedium),
              ],
            ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ],
      ),
    );
  }
}
