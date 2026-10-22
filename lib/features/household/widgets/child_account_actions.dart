import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/parent_verification.dart';
import '../../profile/widgets/current_password_prompt.dart';

/// Opens [child]'s account settings (ManageChildScreen) after a parent
/// check - Face ID / Touch ID, or the math gate - so a child holding the
/// parent's phone can't change their own login or account.
Future<void> openManageChild(BuildContext context, AppUser child) async {
  final ok = await ParentVerification.verify(
    context,
    reason: "Open ${child.name}'s account settings",
    gateReason: "${child.name}'s account settings are for grown-ups. Parents: answer to continue.",
  );
  if (ok && context.mounted) await Navigator.of(context).pushNamed(AppRoutes.manageChild, arguments: child.id);
}

/// Asks the signed-in parent to prove it's them (their own password, or
/// Google/Apple) before a sensitive change to a child's account. The
/// server only accepts these changes right after a fresh sign-in.
Future<bool> confirmParentIdentity(BuildContext context, {required String message}) async {
  final auth = context.read<AuthService>();
  String? password;
  if (auth.hasPasswordLogin) {
    password = await CurrentPasswordPrompt.show(context, message: message);
    if (password == null) return false;
  }
  return auth.confirmIdentity(password: password);
}

/// Permanently deletes [child]'s login, profile, tasks and reward history
/// (server-side: functions/src/account/delete.ts), after a preview, a
/// confirmation and the parent's own password. Returns true once deleted.
Future<bool> confirmDeleteChildAccount(BuildContext context, AppUser child) async {
  final auth = context.read<AuthService>();
  final notices = AppNotice.of(context);
  void show(Object e) => notices.show(e.toString().replaceFirst('Exception: ', ''), tone: NoticeTone.error);

  final AccountDeletionPreview preview;
  try {
    preview = await auth.previewAccountDeletion(childId: child.id);
  } catch (e) {
    show(e);
    return false;
  }
  if (!context.mounted) return false;
  if (!preview.canDelete) {
    show(preview.forbidden ?? preview.blockers.join(' '));
    return false;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text("Delete ${child.name}'s account?"),
      content: Text(
        "This permanently deletes ${child.name}'s login, profile, XP, coins, tasks and reward "
        "history. It can't be undone.",
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        TextButton(
          key: const Key('confirm-delete-child'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    if (!await confirmParentIdentity(context, message: "Enter your password to delete ${child.name}'s account.")) {
      return false;
    }
    await auth.deleteChildAccount(child.id);
    notices.show("${child.name}'s account was deleted.", tone: NoticeTone.success);
    return true;
  } catch (e) {
    show(e);
    return false;
  }
}

/// Removes [child] from the active household after a warning that, once
/// out, this household's parents no longer manage the account. Returns
/// true once removed.
Future<bool> confirmRemoveChildFromHousehold(BuildContext context, AppUser child) async {
  final db = context.read<DatabaseService>();
  final notices = AppNotice.of(context);
  final householdName = db.household?.name ?? 'this household';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('remove-child-dialog'),
      icon: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 32),
      title: Text('Remove ${child.name} from $householdName?'),
      content: Text(
        "${child.name}'s account will no longer be managed by you or the other parents in "
        "$householdName. You won't be able to see their progress, assign them tasks, open Rex "
        "for them, change their login or delete their account.\n\n"
        "Their unfinished tasks here go back to the household pool. Their XP and coins stay "
        "with their account. To come back, they'd have to ask to join again with your invite code.",
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        TextButton(
          key: const Key('confirm-remove-child'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await db.removeMember(child.id);
    notices.show('${child.name} was removed from $householdName.');
    return true;
  } catch (e) {
    notices.show(e.toString().replaceFirst('Exception: ', ''), tone: NoticeTone.error);
    return false;
  }
}
