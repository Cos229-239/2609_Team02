import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

/// Curated set of emoji avatars users can pick between
const List<String> kAvatarEmojiChoices = [
  '🙂', '😄', '😎', '🤓', '🥳', '🤠',
  '👩', '👨', '🧑', '👧', '👦', '🧒',
  '🐶', '🐱', '🦊', '🐼', '🦁', '🐸',
  '⭐', '🚀', '🎮', '⚽', '🎨', '🏆',
];

class AvatarPickerSheet extends StatelessWidget {
  const AvatarPickerSheet({super.key, required this.selected});

  final String selected;

  static Future<String?> show(BuildContext context, {required String selected}) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => AvatarPickerSheet(selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceMd,
          0,
          AppConstants.spaceMd,
          AppConstants.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose an avatar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppConstants.spaceMd),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 6,
              mainAxisSpacing: AppConstants.spaceSm,
              crossAxisSpacing: AppConstants.spaceSm,
              children: [
                for (final emoji in kAvatarEmojiChoices)
                  _AvatarChoice(
                    emoji: emoji,
                    isSelected: emoji == selected,
                    onTap: () => Navigator.of(context).pop(emoji),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({required this.emoji, required this.isSelected, required this.onTap});

  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: AppConstants.emojiIconLg)),
      ),
    );
  }
}
