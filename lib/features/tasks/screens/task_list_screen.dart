import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../widgets/task_tile.dart';

/// "Children's view of tasks assigned" — shows one child's tasks and
/// their earned rewards. Also used by parents (tapping a child from Home
/// or Family) to see that child's task list.
class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key, required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final child = db.userById(childId);
    final tasks = db.tasksForUser(childId);

    if (child == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Child not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text("${child.name}'s Tasks")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    child: Text(child.avatarEmoji, style: const TextStyle(fontSize: AppConstants.emojiIconMd)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hi ${child.name}! 👋', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        )),
                        const SizedBox(height: 4),
                        Text(
                          'Here is what you earned so far!',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600,
                          fontSize: 14,
                          height: 1.0),
                        ),
                      ],
                    ),
                  ),
                  Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  ),
  decoration: BoxDecoration(
  color: Colors.amber.withValues(alpha: 0.08),
  border: Border.all(
    color: Colors.amber.shade200,
    width: 1,
  ),
  borderRadius: BorderRadius.circular(14),
),
  child: Column(
    children: [
      const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
      Text(
        '${child.xp} XP',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text('My Tasks:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            )),
            Text(
              'Complete your tasks to earn more rewards!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 22),
            if (tasks.isNotEmpty)
  const Row(
    children: [
      const Expanded(
        child: SizedBox(),
      ),
      SizedBox(
        width: 72,
        child: Center(
          child: Text('REWARD'),
        ),
      ),
     SizedBox(
  width: 75,
  child: Padding(
    padding: EdgeInsets.only(right: 10),
      child: Text(
        'STATUS',
        textAlign: TextAlign.right,
      ),
    ),
  ),  
    ],
  ),
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No tasks assigned yet.'),
              )
            else
              for (final task in tasks) ...[
                TaskTile(
                  task: task,
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.taskDetail, arguments: task.id),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 25),
            Text('My Rewards:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 20,
            )),
            Text(
              'Earn more points and earn these rewards next!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 125,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: db.availableRewards.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final reward = db.availableRewards[index];
                  final double progress =
                      (child.xp / (reward.xpCost == 0 ? 1 : reward.xpCost)).clamp(0.0, 1.0).toDouble();
                  return SizedBox(
                    width: 110,
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Text(
                            reward.icon,
                            style: const TextStyle(
                            fontSize: 24,
                           ),
                         ),
                        ),
                          const SizedBox(height: 8),
                          Center(
  child: Text(
    reward.title,
    maxLines: 2,
    textAlign: TextAlign.center,
    overflow: TextOverflow.visible,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),
  ),
),
                          const Spacer(),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: progress, minHeight: 5,
                            color: Colors.green,
                            backgroundColor: Colors.green.shade100),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
