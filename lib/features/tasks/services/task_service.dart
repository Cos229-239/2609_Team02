import '../../../core/models/task.dart';
import '../../../core/services/database_service.dart';

/// Task-specific operations layered over [DatabaseService]. Splitting this
/// out keeps the generic data store simple while giving task workflows
/// (assign, complete, approve) a dedicated place to grow — e.g. adding
/// recurrence scheduling later.
class TaskService {
  TaskService(this._db);

  final DatabaseService _db;

  List<TaskModel> tasksForChild(String childId) => _db.tasksForUser(childId);

  TaskModel? taskById(String taskId) {
    for (final task in _db.tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  Future<void> assignTask({
    required String title,
    required String childId,
    int rewardXp = 50,
    String icon = '📋',
  }) {
    return _db.addTask(
      TaskModel(
        id: 'task-${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        assignedToUserId: childId,
        rewardXp: rewardXp,
        icon: icon,
      ),
    );
  }

  Future<void> markComplete(String taskId) => _db.completeTask(taskId);

  Future<void> approve(String taskId) => _db.approveTask(taskId);
}
