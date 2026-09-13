import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/user.dart';
import '../../../core/services/database_service.dart';
import '../widgets/family_member_card.dart';

/// "Family" tab — everyone in the household. Tapping a child opens their
/// task list; this is the placeholder screen for the `household` feature
/// area referenced in the project structure.
///
/// This only returns the tab's content; `MainTabShell` supplies the
/// shared app bar, bottom nav bar and `SafeArea`.
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final household = db.household;

    if (household == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final parents = db.familyMembers.where((m) => m.role == UserRole.parent);
    final children = db.children;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(household.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text('Parents', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final parent in parents) ...[
          FamilyMemberCard(user: parent),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        Text('Kids', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final child in children) ...[
          FamilyMemberCard(
            user: child,
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.taskList, arguments: child.id),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _showInviteCodeDialog(context, household.inviteCode),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add Family Member'),
        ),
      ],
    );
  }

  void _showInviteCodeDialog(BuildContext context, String? inviteCode) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invite Code'),
        content: Text(
          inviteCode == null
              ? 'No invite code available yet.'
              : 'Share this code with a new family member — they\'ll enter it '
                  'as a "Child" when creating their account:\n\n$inviteCode',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
