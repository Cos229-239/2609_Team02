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
    final household = db.household;

    if (household == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Text('Welcome back, $parentName! 👋', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 6),
        Text(
          household.name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600,
          fontSize: 16),
        ),
        const SizedBox(height: 28),
        AppButton(
          label: 'Create a New Task',
          icon: Icons.add_task,
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.taskCreate),
        ),
        const SizedBox(height: 32),
        Text('Your Family', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 14),
        for (final member in db.familyMembers) ...[
          FamilyMemberCard(
            user: member,
            onTap: member.isChild
                ? () => Navigator.of(context).pushNamed(AppRoutes.taskList, arguments: member.id)
                : null,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 125),
        AppCard(
          child:Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children:[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'See how your family is progressing this week.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      height: 1.3,
                      color: Colors.grey.shade800,
                    )
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => MainTabShell.switchTab(context, AppTab.progress),
                  child: const Text(
                  'View',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
