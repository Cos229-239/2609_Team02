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
    required this.assignedToUserId,
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
  final String assignedToUserId;
  final int rewardXp;
  final TaskStatus status;
  final bool isRecurring;
  final DateTime? dueDate;

  bool get isPending => status == TaskStatus.pending;
  bool get isCompleted =>
      status == TaskStatus.completed || status == TaskStatus.approved;

  factory TaskModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return TaskModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      assignedToUserId: data['assignedToUserId'] as String? ?? '',
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

  TaskModel copyWith({
    String? title,
    String? description,
    String? icon,
    int? rewardXp,
    TaskStatus? status,
    bool? isRecurring,
    DateTime? dueDate,
  }) {
    return TaskModel(
      id: id,
      title: title ?? this.title,
      assignedToUserId: assignedToUserId,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      rewardXp: rewardXp ?? this.rewardXp,
      status: status ?? this.status,
      isRecurring: isRecurring ?? this.isRecurring,
      dueDate: dueDate ?? this.dueDate,
    );
  }
}
