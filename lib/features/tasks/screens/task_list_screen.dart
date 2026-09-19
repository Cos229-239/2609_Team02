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
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    child: Text(child.avatarEmoji, style: const TextStyle(fontSize: AppConstants.emojiIconMd)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hi ${child.name}! 👋', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          'Here are your tasks and the rewards you can earn!',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 10,
  ),
  decoration: BoxDecoration(
    border: Border.all(color: Colors.grey.shade300),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Column(
    children: [
      const Icon(Icons.star, color: Colors.amber),
      Text(
        '${child.xp} XP',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  ),
),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('My Tasks', style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Complete your tasks to earn awesome rewards!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            if (tasks.isNotEmpty)
  const Row(
    children: [
      Expanded(
        child: Text('TASK'),
      ),
      Text('REWARD'),
      SizedBox(width: 24),
      Text('STATUS'),
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
            const SizedBox(height: 20),
            Text('My Rewards', style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Earn points and get amazing rewards!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: db.availableRewards.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final reward = db.availableRewards[index];
                  final double progress =
                      (child.xp / (reward.xpCost == 0 ? 1 : reward.xpCost)).clamp(0.0, 1.0).toDouble();
                  return SizedBox(
                    width: 110,
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(reward.icon, style: const TextStyle(fontSize: AppConstants.emojiIconSm)),
                          const SizedBox(height: 4),
                          Text(
                            reward.title,
                            maxLines: 2,
                            overflow: TextOverflow.visible,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: progress, minHeight: 5),
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
