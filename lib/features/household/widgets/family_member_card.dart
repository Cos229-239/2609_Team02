import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/user.dart';
import '../../../shared/widgets/app_card.dart';

/// Reusable row showing one family member's avatar, name/role and XP:
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
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
            child: Text(user.avatarEmoji, style: const TextStyle(fontSize: AppConstants.emojiIconMd)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600
                )),
                const SizedBox(height: 2),
                Text(
                  user.isParent ? 'Parent' : 'Age ${user.age ?? '-'}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (user.isChild)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 17),
                    const SizedBox(width: 4),
                    Text('${user.xp} XP', style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade700,
                    )),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monetization_on, color: Colors.amber.shade700, size: 14),
                    const SizedBox(width: 3),
                    Text('${user.coins}', style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    )),
                  ],
                ),
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
