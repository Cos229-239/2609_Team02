import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/layouts/main_tab_shell.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../widgets/family_member_card.dart';

/// "Home" tab — the parent's dashboard. Surfaces a quick family summary
/// and the primary "assign tasks" action from the wireframes, plus quick
/// access into each child's task list.
///
/// This only returns the tab's content; [MainTabShell] supplies the
/// shared app bar, bottom nav bar and [SafeArea].
class HouseholdHomeScreen extends StatelessWidget {
  const HouseholdHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final db = context.watch<DatabaseService>();
    final parentName = auth.currentUser?.name ?? 'there';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Welcome back, $parentName! 👋', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          db.household.name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        AppButton(
          label: 'Assign Tasks',
          icon: Icons.add_task,
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.taskCreate),
        ),
        const SizedBox(height: 24),
        Text('Your Family', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final member in db.familyMembers) ...[
          FamilyMemberCard(
            user: member,
            onTap: member.isChild
                ? () => Navigator.of(context).pushNamed(AppRoutes.taskList, arguments: member.id)
                : null,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        AppCard(
          child: Row(
            children: [
              Icon(Icons.bar_chart, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'See how the whole family is progressing this week.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () => MainTabShell.switchTab(context, AppTab.progress),
                child: const Text('View'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
