import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of an assigned chore/quest.
enum TaskStatus {
  /// Assigned, not started/completed by the child yet.
  pending,

  /// Child marked it done; waiting on a parent to approve.
  completed,

  /// Parent approved — XP/rewards have been granted.
  approved,
}

class TaskModel {
  const TaskModel({
    required this.id,
    required this.title,
    this.assignedToUserId,
    this.description = '',
    this.icon = '🧹',
    this.rewardXp = 50,
    this.status = TaskStatus.pending,
    this.isRecurring = false,
    this.dueDate,
  });

  final String id;
  final String title;
  final String description;

  /// Emoji used as a lightweight placeholder icon
  final String icon;

  /// Who this task belongs to. Null means it's sitting in the household's
  /// shared pool — any child in the family can claim it (see
  /// [DatabaseService.claimTask]) instead of a parent assigning it
  /// directly to one child.
  final String? assignedToUserId;
  final int rewardXp;
  final TaskStatus status;
  final bool isRecurring;
  final DateTime? dueDate;

  bool get isCompleted =>
      status == TaskStatus.completed || status == TaskStatus.approved;

  /// True when nobody has claimed this task yet.
  bool get isAvailable => assignedToUserId == null;

  factory TaskModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return TaskModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      assignedToUserId: data['assignedToUserId'] as String?,
      description: data['description'] as String? ?? '',
      icon: data['icon'] as String? ?? '🧹',
      rewardXp: data['rewardXp'] as int? ?? 50,
      status: TaskStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => TaskStatus.pending,
      ),
      isRecurring: data['isRecurring'] as bool? ?? false,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'assignedToUserId': assignedToUserId,
      'description': description,
      'icon': icon,
      'rewardXp': rewardXp,
      'status': status.name,
      'isRecurring': isRecurring,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
    };
  }

  /// Seeded into a household's `tasks` subcollection when it's created, so
  /// kids have a starter pool of unclaimed chores to grab from (matching
  /// the "Available Tasks" section of the child task list).
  static List<TaskModel> defaultAvailableCatalog(DateTime now) {
    return [
      TaskModel(
        id: 'seed-trash',
        title: 'Take Out the Trash',
        icon: '🗑️',
        rewardXp: 25,
        dueDate: now.add(const Duration(days: 1)),
        isRecurring: true,
      ),
      TaskModel(
        id: 'seed-table',
        title: 'Set the Table',
        icon: '🍽️',
        rewardXp: 20,
        dueDate: now.add(const Duration(days: 1)),
        isRecurring: true,
      ),
      TaskModel(
        id: 'seed-dog',
        title: 'Feed the Dog',
        icon: '🐾',
        rewardXp: 15,
        dueDate: now.add(const Duration(days: 2)),
        isRecurring: true,
      ),
      TaskModel(
        id: 'seed-read',
        title: 'Read for 20 Minutes',
        icon: '📖',
        rewardXp: 20,
        dueDate: now.add(const Duration(days: 3)),
      ),
    ];
  }
}
