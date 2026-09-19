import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(user.avatarEmoji, style: const TextStyle(fontSize: AppConstants.emojiIconMd)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600
                )),
                const SizedBox(height: 3),
                Text(
                  user.isParent ? 'Parent' : 'Age ${user.age ?? '—'}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (user.isChild)
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 17),
                const SizedBox(width: 4),
                Text('${user.xp} XP', style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade700,
                )),
              ],
            ),
          if (onTap != null) ...[
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey,
              size: 26,
            ),
          ],
        ],
      ),
    );
  }
}
