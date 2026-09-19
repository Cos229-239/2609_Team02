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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(household.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
        
       const SizedBox(height: 2),
Text(
  'Manage your family members',
  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
    color: Colors.grey.shade600,
    fontSize: 14,
  ),
),
const SizedBox(height: 24),
Row(
  children: [
    Icon(
      Icons.supervisor_account_rounded,
      size: 20,
      color: Theme.of(context).colorScheme.primary,
    ),
    const SizedBox(width: 10),
    Text(
      'Parents',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ],
),
        const SizedBox(height: 10),
        for (final parent in parents) ...[
          FamilyMemberCard(user: parent),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 18),
       Row(
  children: [
    Icon(
      Icons.child_care_rounded,
      size: 20,
      color: Theme.of(context).colorScheme.primary,
    ),
    const SizedBox(width: 8),
    Text(
      'Children',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ],
),
        const SizedBox(height: 10),
        for (final child in children) ...[
          FamilyMemberCard(
            user: child,
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.taskList, arguments: child.id),
          ),
          const SizedBox(height: 8),
        ],
        const Spacer(),
        OutlinedButton.icon(
  onPressed: () => _showInviteCodeDialog(context, household.inviteCode),
  icon: const Icon(Icons.person_add_alt, size: 20),
  label: const Text(
    'Add Family Member',
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  ),
  style: OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 13),
    foregroundColor: const Color(0xFF2563EB),
    side: const BorderSide(color: Color(0xFF2563EB),
    width: 1,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
  ),
),
      ],
    ),
    );
  }

  void _showInviteCodeDialog(BuildContext context, String? inviteCode) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(20),
),
contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: const Row(
  children: [
    Icon(Icons.group_add_rounded, size: 24),
    SizedBox(width: 10),
    Text(
      'Invite Family Member',
      style: TextStyle(fontWeight: FontWeight.w600),
    ),
  ],
),
        content: Text(
  inviteCode == null
      ? 'No invite code available yet.'
      : 'Share this code with a family member so they can join your household:\n\n$inviteCode',
  style: const TextStyle(
    fontSize: 15,
    height: 1.4,
  ),
),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
             'Close',
            style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
    ),
  ),
),
        ],
      ),
    );
  }
}
