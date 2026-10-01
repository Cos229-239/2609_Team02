import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../constants/task_icons.dart';

/// How often a repeating task comes back.
enum TaskRepeat {
  daily('Every day', 'Daily Task'),
  everyOtherDay('Every other day', 'Every Other Day'),
  weekly('Weekly', 'Weekly Task'),
  everyOtherWeek('Every other week', 'Every Other Week'),
  monthly('Monthly', 'Monthly Task');

  const TaskRepeat(this.label, this.taskLabel);

  /// Option label in the repeat picker.
  final String label;

  /// Short tag shown on a task card ("Daily Task" vs "One-time Task").
  final String taskLabel;

  /// Weekly cadences repeat on chosen weekdays.
  bool get usesWeekdays => this == TaskRepeat.weekly || this == TaskRepeat.everyOtherWeek;

  static TaskRepeat? fromName(Object? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// Short names indexed by [DateTime.weekday] (1 = Monday … 7 = Sunday).
const List<String> weekdayShortNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A calendar day as stored in Firestore: 'YYYY-MM-DD'.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Parses [dayKey] output back to local midnight; null if malformed.
DateTime? parseDayKey(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// A repeating task: `households/{id}/taskSchedules/{id}`.
///
/// The app only stores the rule. Cloud Functions (functions/src/index.ts)
/// create one ordinary [TaskModel] per occurrence, a day ahead, at 9 AM in
/// the household's time zone — each is completed and approved on its own and
/// links back here via [TaskModel.scheduleId].
class TaskSchedule {
  const TaskSchedule({
    required this.id,
    required this.title,
    required this.repeat,
    required this.startDate,
    this.description = '',
    this.icon = TaskIconCatalog.defaultKey,
    this.rewardXp = AppConstants.defaultTaskXp,
    this.coinReward = AppConstants.defaultTaskCoins,
    this.assignedToUserId,
    this.weekdays = const [],
    this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final int rewardXp;
  final int coinReward;

  /// Who each occurrence goes to; null puts it in the shared pool.
  final String? assignedToUserId;

  final TaskRepeat repeat;

  /// [DateTime.weekday] values (1 = Monday … 7 = Sunday) for weekly cadences.
  final List<int> weekdays;

  /// First day it can occur (date only).
  final DateTime startDate;

  final DateTime? createdAt;

  /// Weekdays it actually repeats on: weekly with none picked uses the start day.
  List<int> get effectiveWeekdays {
    final days = weekdays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
    return days.isEmpty ? [startDate.weekday] : days;
  }

  /// "Every day", "Every Mon & Thu", "Every other Tue", "Monthly on the 31st".
  String describe() {
    switch (repeat) {
      case TaskRepeat.daily:
      case TaskRepeat.everyOtherDay:
        return repeat.label;
      case TaskRepeat.weekly:
        final days = effectiveWeekdays;
        if (days.length == 7) return 'Every day';
        return 'Every ${_joinDays(days)}';
      case TaskRepeat.everyOtherWeek:
        return 'Every other ${_joinDays(effectiveWeekdays)}';
      case TaskRepeat.monthly:
        return 'Monthly on the ${_ordinal(startDate.day)}';
    }
  }

  static String _joinDays(List<int> days) {
    final names = days.map((d) => weekdayShortNames[d]).toList();
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }

  TaskSchedule copyWith({
    String? title,
    String? description,
    String? icon,
    int? rewardXp,
    int? coinReward,
    String? assignedToUserId,
    bool clearAssignedToUserId = false,
    TaskRepeat? repeat,
    List<int>? weekdays,
    DateTime? startDate,
  }) {
    return TaskSchedule(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      rewardXp: rewardXp ?? this.rewardXp,
      coinReward: coinReward ?? this.coinReward,
      assignedToUserId: clearAssignedToUserId ? null : (assignedToUserId ?? this.assignedToUserId),
      repeat: repeat ?? this.repeat,
      weekdays: weekdays ?? this.weekdays,
      startDate: startDate ?? this.startDate,
      createdAt: createdAt,
    );
  }

  /// Null for docs with an unknown repeat or a bad start date.
  static TaskSchedule? fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final repeat = TaskRepeat.fromName(data['repeat']);
    final start = parseDayKey(data['startDate']);
    if (repeat == null || start == null) return null;
    return TaskSchedule(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      icon: data['icon'] as String? ?? TaskIconCatalog.defaultKey,
      rewardXp: data['rewardXp'] as int? ?? AppConstants.defaultTaskXp,
      coinReward: data['coinReward'] as int? ?? AppConstants.defaultTaskCoins,
      assignedToUserId: data['assignedToUserId'] as String?,
      repeat: repeat,
      weekdays: List<int>.from((data['weekdays'] as List? ?? const []).whereType<int>()),
      startDate: start,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Excludes the server's `generatedThrough` bookkeeping, so updates keep it.
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'icon': icon,
      'rewardXp': rewardXp,
      'coinReward': coinReward,
      'assignedToUserId': assignedToUserId,
      'repeat': repeat.name,
      'weekdays': repeat.usesWeekdays ? effectiveWeekdays : <int>[],
      'startDate': dayKey(startDate),
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    };
  }

  /// Starter repeating chores for a new household's shared pool.
  static List<TaskSchedule> defaultCatalog(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return [
      TaskSchedule(
        id: 'seed-trash',
        title: 'Take Out the Trash',
        icon: 'trash',
        rewardXp: 25,
        coinReward: 5,
        repeat: TaskRepeat.weekly,
        weekdays: const [DateTime.monday, DateTime.thursday],
        startDate: today,
        createdAt: now,
      ),
      TaskSchedule(
        id: 'seed-table',
        title: 'Set the Table',
        icon: 'table',
        rewardXp: 20,
        coinReward: 5,
        repeat: TaskRepeat.daily,
        startDate: today,
        createdAt: now,
      ),
      TaskSchedule(
        id: 'seed-dog',
        title: 'Feed the Dog',
        icon: 'pet',
        rewardXp: 15,
        coinReward: 5,
        repeat: TaskRepeat.daily,
        startDate: today,
        createdAt: now,
      ),
    ];
  }
}
