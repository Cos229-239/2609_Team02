import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../constants/task_icons.dart';
import 'task_schedule.dart';

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
    this.repeat,
    this.scheduleId,
    this.dueDate,
    this.createdAt,
    this.archived = false,
    this.completedAt,
    this.approvedAt,
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

  /// Cadence of the repeating task this is one occurrence of; null = one-time.
  final TaskRepeat? repeat;

  /// The [TaskSchedule] that generated this occurrence; null = one-time task.
  final String? scheduleId;

  /// Local midnight of the due day.
  final DateTime? dueDate;

  /// Tasks are deleted [AppConstants.taskDeleteAfterDays] after this: see
  /// [isAgedOut].
  final DateTime? createdAt;

  /// When the child marked it done (status went to `completed`).
  final DateTime? completedAt;

  /// When a parent approved it. Approved tasks drop out of task lists
  /// [AppConstants.doneTaskVisibleDays] after this: see [isStaleDone].
  final DateTime? approvedAt;

  /// Manually archived by a parent, independent of [isAgedOut].
  final bool archived;

  /// One occurrence of a repeating task (see [TaskSchedule]).
  bool get isRecurring => scheduleId != null;

  /// An occurrence for a future day. The server creates them a day ahead
  /// so they're ready at midnight; until then they stay hidden.
  bool get isUpcoming {
    final due = dueDate;
    if (!isRecurring || due == null) return false;
    final now = DateTime.now();
    return DateTime(due.year, due.month, due.day).isAfter(DateTime(now.year, now.month, now.day));
  }

  /// "Daily Task", "Weekly Task", … or "One-time Task".
  String get repeatLabel => repeat?.taskLabel ?? (isRecurring ? 'Repeating Task' : 'One-time Task');

  bool get isCompleted =>
      status == TaskStatus.completed || status == TaskStatus.approved;

  /// True when nobody has claimed this task yet.
  bool get isAvailable => assignedToUserId == null;

  /// True once older than [AppConstants.taskDeleteAfterDays] days. Such
  /// tasks are hidden everywhere and deleted (server daily run, plus a sweep
  /// from a parent's device) for data privacy.
  bool get isAgedOut {
    final created = createdAt ?? dueDate;
    if (created == null) return false;
    return DateTime.now().difference(created).inDays >
        AppConstants.taskDeleteAfterDays;
  }

  /// Best guess at when this task was finished, for tasks saved before
  /// [approvedAt]/[completedAt] existed.
  DateTime? get finishedAt => approvedAt ?? completedAt ?? dueDate ?? createdAt;

  /// An approved task finished more than [AppConstants.doneTaskVisibleDays]
  /// days ago: no longer shown in task lists (XP/coins are kept, of course).
  bool get isStaleDone {
    if (status != TaskStatus.approved) return false;
    final at = finishedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) >
        const Duration(days: AppConstants.doneTaskVisibleDays);
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
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? createdAt,
    bool? archived,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? approvedAt,
    bool clearApprovedAt = false,
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
      repeat: repeat,
      scheduleId: scheduleId,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      createdAt: createdAt ?? this.createdAt,
      archived: archived ?? this.archived,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      approvedAt: clearApprovedAt ? null : (approvedAt ?? this.approvedAt),
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
      repeat: TaskRepeat.fromName(data['repeat']),
      scheduleId: data['scheduleId'] as String?,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      archived: data['archived'] as bool? ?? false,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
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
      'repeat': repeat?.name,
      'scheduleId': scheduleId,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'archived': archived,
      'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      'approvedAt': approvedAt == null ? null : Timestamp.fromDate(approvedAt!),
    };
  }

  /// One-off seed tasks for a new household's shared pool. (The repeating
  /// starters are [TaskSchedule.defaultCatalog].)
  ///
  /// Due dates are local midnight of the due day, like the ones the date
  /// picker produces: reminders are planned per local day.
  static List<TaskModel> defaultAvailableCatalog(DateTime now) {
    return [
      TaskModel(
        id: 'seed-read',
        title: 'Read for 20 Minutes',
        icon: 'reading',
        rewardXp: 20,
        coinReward: 5,
        dueDate: DateTime(now.year, now.month, now.day + 3),
        createdAt: now,
      ),
    ];
  }
}
