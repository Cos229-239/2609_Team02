import 'package:flutter/material.dart';

import '../widgets/task_view_card.dart';

/// Full-screen task view, used when a task is opened by route (e.g. from a
/// push notification). Tapping a task tile in the app opens the same
/// [TaskViewCard] as a bottom sheet instead (see [showTaskViewSheet]).
class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task Details')),
      body: SafeArea(child: TaskViewCard(taskId: taskId)),
    );
  }
}
