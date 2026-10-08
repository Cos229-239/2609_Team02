import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/task.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/layouts/main_tab_shell.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../tasks/widgets/task_swipe.dart';
import '../../tasks/widgets/task_tile.dart';
import '../widgets/family_member_card.dart';

/// "Home" tab: the parent's dashboard. Surfaces a quick family summary
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
    final needsApproval = db.activeTasks
        .where((t) => t.status == TaskStatus.completed)
        .toList(growable: false);

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
        const SizedBox(height: 20),
        if (db.unacknowledgedRedemptions.isNotEmpty) ...[
          AppCard(
            onTap: () => MainTabShell.switchTab(context, AppTab.family),
            color: Colors.amber.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    db.unacknowledgedRedemptions.length == 1
                        ? '1 reward was just redeemed - tap to review in Family.'
                        : '${db.unacknowledgedRedemptions.length} rewards were just redeemed - tap to review in Family.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        AppButton(
          label: 'Create a New Task',
          icon: Icons.add_task,
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.taskCreate),
        ),
        if (db.isAdmin && db.joinRequests.isNotEmpty) ...[
          const SizedBox(height: 16),
          AppCard(
            onTap: () => MainTabShell.switchTab(context, AppTab.family),
            color: Colors.orange.withValues(alpha: 0.10),
            child: Row(
              children: [
                const Icon(Icons.how_to_reg_outlined, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    db.joinRequests.length == 1
                        ? '${db.joinRequests.first.name} wants to join - tap to review.'
                        : '${db.joinRequests.length} people want to join - tap to review.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ],
        if (needsApproval.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text('Needs Approval:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 4),
          Text(
            'Swipe right to approve, left to delete.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          for (final task in needsApproval) ...[
            ParentTaskSwipe(
              task: task,
              child: TaskTile(
                task: task,
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.taskDetail, arguments: task.id),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (db.schedules.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text('Repeating Tasks:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 4),
          Text(
            "Each day's task shows up that morning; reminders go out at 9 AM.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          for (final schedule in db.schedules) ...[
            AppCard(
                padding: EdgeInsets.symmetric(
                  horizontal: 16, 
                  vertical: 8,
                ),
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.scheduleEdit, arguments: schedule.id),
                child: Row(
                children: [
                  Icon(Icons.repeat, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(schedule.title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          '${schedule.describe()} • ${db.userById(schedule.assignedToUserId ?? '')?.name ?? 'Household'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 32),
        Text('Your Family:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 22,
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
