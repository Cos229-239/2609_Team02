import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/models/user.dart';

/// Parent hands this device to [child]: opens Rex's Room in kid mode
/// (see [RexRoomScreen]) after a short heads-up. Leaving needs the
/// parental gate.
Future<void> startRexKidMode(BuildContext context, AppUser child) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('rex-kid-mode-dialog'),
      title: Text("Open Rex for ${child.name}?"),
      content: Text(
        '${child.avatarEmoji} Hand your device to ${child.name}. They can play with Rex and do '
        "their tasks; finished tasks still come to you for approval.\n\n"
        "To leave Rex's Room, a grown-up answers a quick question.",
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('rex-kid-mode-start'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Start'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(context).pushNamed(AppRoutes.rexRoom, arguments: child.id);
  }
}
