import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../constants/task_icons.dart';

/// Lifecycle of an assigned chore/quest.
enum TaskStatus { pending, completed, approved }

class TaskModel {
  const TaskModel({
    required this.id,
    required this.title,
    this.assignedToUserId,
    this.description = '',
    this.icon = TaskIconCatalog.defaultKey,
    this.rewardXp = AppConstants.defaultTaskXp,
    this.coinReward = AppConstants.defaultTaskCoins,
    this.status = TaskStatus.pending,
    this.isRecurring = false,
    this.dueDate,
    this.createdAt,
    this.archived = false,
  });

  final String id;
  final String title;
  final String description;

  /// Key into [TaskIconCatalog].
  final String icon;

  /// Null means unclaimed, sitting in the household's shared pool.
  final String? assignedToUserId;

  /// XP granted on approval.
  final int rewardXp;

  /// Coins granted on approval, spent later on rewards.
  final int coinReward;

  final TaskStatus status;
  final bool isRecurring;
  final DateTime? dueDate;

  /// Used to auto-archive stale tasks: see [isArchived].
  final DateTime? createdAt;

  /// Manually archived by a parent, independent of [isAgedOut].
  final bool archived;

  bool get isCompleted =>
      status == TaskStatus.completed || status == TaskStatus.approved;

  /// True when nobody has claimed this task yet.
  bool get isAvailable => assignedToUserId == null;

  /// True once older than [AppConstants.taskArchiveAfterDays] days.
  bool get isAgedOut {
    final created = createdAt;
    if (created == null) return false;
    return DateTime.now().difference(created).inDays >
        AppConstants.taskArchiveAfterDays;
  }

  /// Archived manually or aged out: see [archived] and [isAgedOut].
  bool get isArchived => archived || isAgedOut;

  TaskModel copyWith({
    String? title,
    String? description,
    String? icon,
    String? assignedToUserId,
    bool clearAssignedToUserId = false,
    int? rewardXp,
    int? coinReward,
    TaskStatus? status,
    bool? isRecurring,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? createdAt,
    bool? archived,
  }) {
    return TaskModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      assignedToUserId: clearAssignedToUserId
          ? null
          : (assignedToUserId ?? this.assignedToUserId),
      rewardXp: rewardXp ?? this.rewardXp,
      coinReward: coinReward ?? this.coinReward,
      status: status ?? this.status,
      isRecurring: isRecurring ?? this.isRecurring,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      createdAt: createdAt ?? this.createdAt,
      archived: archived ?? this.archived,
    );
  }

  factory TaskModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return TaskModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      assignedToUserId: data['assignedToUserId'] as String?,
      description: data['description'] as String? ?? '',
      icon: data['icon'] as String? ?? TaskIconCatalog.defaultKey,
      rewardXp: data['rewardXp'] as int? ?? AppConstants.defaultTaskXp,
      coinReward: data['coinReward'] as int? ?? AppConstants.defaultTaskCoins,
      status: TaskStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => TaskStatus.pending,
      ),
      isRecurring: data['isRecurring'] as bool? ?? false,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      archived: data['archived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'assignedToUserId': assignedToUserId,
      'description': description,
      'icon': icon,
      'rewardXp': rewardXp,
      'coinReward': coinReward,
      'status': status.name,
      'isRecurring': isRecurring,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'archived': archived,
    };
  }

  /// Seed data for a new household's shared task pool.
  static List<TaskModel> defaultAvailableCatalog(DateTime now) {
    return [
      TaskModel(
        id: 'seed-trash',
        title: 'Take Out the Trash',
        icon: 'trash',
        rewardXp: 25,
        coinReward: 5,
        dueDate: now.add(const Duration(days: 1)),
        isRecurring: true,
        createdAt: now,
      ),
      TaskModel(
        id: 'seed-table',
        title: 'Set the Table',
        icon: 'table',
        rewardXp: 20,
        coinReward: 5,
        dueDate: now.add(const Duration(days: 1)),
        isRecurring: true,
        createdAt: now,
      ),
      TaskModel(
        id: 'seed-dog',
        title: 'Feed the Dog',
        icon: 'pet',
        rewardXp: 15,
        coinReward: 5,
        dueDate: now.add(const Duration(days: 2)),
        isRecurring: true,
        createdAt: now,
      ),
      TaskModel(
        id: 'seed-read',
        title: 'Read for 20 Minutes',
        icon: 'reading',
        rewardXp: 20,
        coinReward: 5,
        dueDate: now.add(const Duration(days: 3)),
        createdAt: now,
      ),
    ];
  }
}
