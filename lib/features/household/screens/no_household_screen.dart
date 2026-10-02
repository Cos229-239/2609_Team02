import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../widgets/household_actions.dart';

/// Shown in place of the tabs while the signed-in user isn't in any
/// household yet: typically right after signing up with an invite code,
/// until the household's admin approves them.
class NoHouseholdScreen extends StatelessWidget {
  const NoHouseholdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final db = context.watch<DatabaseService>();
    final user = auth.currentUser;
    final waiting = db.myPendingRequests;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          waiting.isEmpty ? 'Join your family' : 'Almost there! ⏳',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          waiting.isEmpty
              ? "You're not part of a household yet. Ask a parent for their invite code"
                  '${user?.isParent ?? false ? ', or start your own household' : ''}.'
              : "Your request was sent. As soon as the household's admin approves you, "
                  'your tasks and rewards will show up here.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 20),
        for (final r in waiting) ...[
          PendingRequestTile(request: r),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        const JoinHouseholdCard(),
        if (user?.isParent ?? false) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showCreateHouseholdDialog(context),
            icon: const Icon(Icons.add_home_outlined),
            label: const Text('Create my own household'),
          ),
        ],
        const SizedBox(height: 32),
        TextButton.icon(
          onPressed: () async {
            await context.read<AuthService>().logout();
            if (context.mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log Out'),
        ),
      ],
    );
  }
}
