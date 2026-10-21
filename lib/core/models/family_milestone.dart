import 'package:cloud_firestore/cloud_firestore.dart';

/// Stored lifecycle of a [FamilyMilestone]. `upcoming` and `expired` are
/// derived from the dates (see [MilestonePhase]) so a deadline passing never
/// needs a write.
enum MilestoneStatus { active, paused, completed, cancelled }

/// What the family sees: the stored status combined with the dates.
enum MilestonePhase { upcoming, active, paused, expired, completed, cancelled }

/// Which repeating tasks move the board.
enum RepeatingEligibility { all, selected, none }

/// Which approved tasks count toward a milestone.
class MilestoneEligibility {
  const MilestoneEligibility({
    this.oneTimeTasks = true,
    this.repeating = RepeatingEligibility.all,
    this.scheduleIds = const [],
  });

  /// One-time (non-repeating) tasks count.
  final bool oneTimeTasks;

  final RepeatingEligibility repeating;

  /// Repeating tasks that count when [repeating] is `selected`.
  final List<String> scheduleIds;

  /// Whether a task occurrence (with [scheduleId], null for one-time tasks)
  /// is eligible.
  bool allows(String? scheduleId) {
    if (scheduleId == null) return oneTimeTasks;
    return switch (repeating) {
      RepeatingEligibility.all => true,
      RepeatingEligibility.none => false,
      RepeatingEligibility.selected => scheduleIds.contains(scheduleId),
    };
  }

  bool get countsAnything =>
      oneTimeTasks ||
      repeating == RepeatingEligibility.all ||
      (repeating == RepeatingEligibility.selected && scheduleIds.isNotEmpty);

  MilestoneEligibility copyWith({
    bool? oneTimeTasks,
    RepeatingEligibility? repeating,
    List<String>? scheduleIds,
  }) {
    return MilestoneEligibility(
      oneTimeTasks: oneTimeTasks ?? this.oneTimeTasks,
      repeating: repeating ?? this.repeating,
      scheduleIds: scheduleIds ?? this.scheduleIds,
    );
  }

  factory MilestoneEligibility.fromMap(Object? raw) {
    if (raw is! Map) return const MilestoneEligibility();
    return MilestoneEligibility(
      oneTimeTasks: raw['oneTimeTasks'] as bool? ?? true,
      repeating: RepeatingEligibility.values.firstWhere(
        (r) => r.name == raw['repeating'],
        orElse: () => RepeatingEligibility.all,
      ),
      scheduleIds: List<String>.from(
        (raw['scheduleIds'] as List? ?? const []).whereType<String>(),
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'oneTimeTasks': oneTimeTasks,
    'repeating': repeating.name,
    'scheduleIds': scheduleIds,
  };
}

/// A shared household goal ("Family Goal"): every eligible approved task
/// moves the family's game piece along a board toward a shared reward.
///
/// Stored at `households/{householdId}/milestones/{milestoneId}`; its audit
/// trail is the `contributions` subcollection (see [MilestoneContribution]).
/// Design notes: Documents/Family_Milestones_and_MiniGames.md.
class FamilyMilestone {
  const FamilyMilestone({
    required this.id,
    required this.title,
    required this.rewardTitle,
    required this.startsAt,
    required this.endsAt,
    this.description = '',
    this.illustration = '🎡',
    this.rewardIcon = '🎁',
    this.boardLength = defaultBoardLength,
    this.spacesPerTask = 1,
    this.eligibility = const MilestoneEligibility(),
    this.participantIds = const [],
    this.status = MilestoneStatus.active,
    this.position = 0,
    this.createdBy,
    this.createdAt,
    this.completedAt,
    this.rewardClaimedAt,
    this.rewardClaimedBy,
    this.endedReason,
  });

  static const int minBoardLength = 5;
  static const int maxBoardLength = 60;
  static const int defaultBoardLength = 20;
  static const int maxSpacesPerTask = 3;
  static const int titleMaxLength = 60;

  /// Tasks finished before the deadline still count if a parent approves
  /// them within this long after it.
  static const Duration approvalGrace = Duration(hours: 48);

  final String id;
  final String title;
  final String description;

  /// Emoji illustrating the goal (shown at the board's finish).
  final String illustration;

  /// The shared reward the family unlocks, e.g. "Amusement park day".
  final String rewardTitle;
  final String rewardIcon;

  /// First instant that counts (local midnight of the start day).
  final DateTime startsAt;

  /// Exclusive end: local midnight after the deadline day.
  final DateTime endsAt;

  /// Number of spaces from Start (0) to the finish.
  final int boardLength;

  /// Spaces one eligible approved task moves the piece.
  final int spacesPerTask;

  final MilestoneEligibility eligibility;

  /// Children whose tasks count; empty = every child in the household.
  final List<String> participantIds;

  final MilestoneStatus status;

  /// Current space, 0..[boardLength].
  final int position;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? completedAt;

  /// When a parent marked the shared reward as enjoyed/claimed.
  final DateTime? rewardClaimedAt;
  final String? rewardClaimedBy;

  /// Why a milestone was closed without finishing (cancelled/replaced/restarted).
  final String? endedReason;

  bool get isFinished => position >= boardLength;
  bool get isCompleted => status == MilestoneStatus.completed;
  bool get isRewardClaimed => rewardClaimedAt != null;

  /// Stored status active/paused: this is the household's current goal.
  bool get isCurrent =>
      status == MilestoneStatus.active || status == MilestoneStatus.paused;

  int get spacesLeft => (boardLength - position).clamp(0, boardLength);

  double get progress => boardLength == 0 ? 0 : (position / boardLength).clamp(0.0, 1.0);

  /// The deadline day (the day before [endsAt]).
  DateTime get deadlineDay {
    final last = endsAt.subtract(const Duration(hours: 12));
    return DateTime(last.year, last.month, last.day);
  }

  MilestonePhase phaseAt(DateTime now) {
    switch (status) {
      case MilestoneStatus.completed:
        return MilestonePhase.completed;
      case MilestoneStatus.cancelled:
        return MilestonePhase.cancelled;
      case MilestoneStatus.paused:
        return now.isBefore(endsAt) ? MilestonePhase.paused : MilestonePhase.expired;
      case MilestoneStatus.active:
        if (now.isBefore(startsAt)) return MilestonePhase.upcoming;
        if (!now.isBefore(endsAt)) return MilestonePhase.expired;
        return MilestonePhase.active;
    }
  }

  FamilyMilestone copyWith({
    String? title,
    String? description,
    String? illustration,
    String? rewardTitle,
    String? rewardIcon,
    DateTime? startsAt,
    DateTime? endsAt,
    int? boardLength,
    int? spacesPerTask,
    MilestoneEligibility? eligibility,
    List<String>? participantIds,
    MilestoneStatus? status,
    int? position,
  }) {
    return FamilyMilestone(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      illustration: illustration ?? this.illustration,
      rewardTitle: rewardTitle ?? this.rewardTitle,
      rewardIcon: rewardIcon ?? this.rewardIcon,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      boardLength: boardLength ?? this.boardLength,
      spacesPerTask: spacesPerTask ?? this.spacesPerTask,
      eligibility: eligibility ?? this.eligibility,
      participantIds: participantIds ?? this.participantIds,
      status: status ?? this.status,
      position: position ?? this.position,
      createdBy: createdBy,
      createdAt: createdAt,
      completedAt: completedAt,
      rewardClaimedAt: rewardClaimedAt,
      rewardClaimedBy: rewardClaimedBy,
      endedReason: endedReason,
    );
  }

  factory FamilyMilestone.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) =>
      FamilyMilestone.fromMap(doc.id, doc.data() ?? const {});

  factory FamilyMilestone.fromMap(String id, Map<String, dynamic> data) {
    DateTime? time(String key) => (data[key] as Timestamp?)?.toDate();
    final boardLength = (data['boardLength'] as int? ?? defaultBoardLength)
        .clamp(minBoardLength, maxBoardLength);
    return FamilyMilestone(
      id: id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      illustration: data['illustration'] as String? ?? '🎡',
      rewardTitle: data['rewardTitle'] as String? ?? '',
      rewardIcon: data['rewardIcon'] as String? ?? '🎁',
      startsAt: time('startsAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      endsAt: time('endsAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      boardLength: boardLength,
      spacesPerTask: (data['spacesPerTask'] as int? ?? 1).clamp(1, maxSpacesPerTask),
      eligibility: MilestoneEligibility.fromMap(data['eligibility']),
      participantIds: List<String>.from(
        (data['participantIds'] as List? ?? const []).whereType<String>(),
      ),
      status: MilestoneStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => MilestoneStatus.active,
      ),
      position: (data['position'] as int? ?? 0).clamp(0, boardLength),
      createdBy: data['createdBy'] as String?,
      createdAt: time('createdAt'),
      completedAt: time('completedAt'),
      rewardClaimedAt: time('rewardClaimedAt'),
      rewardClaimedBy: data['rewardClaimedBy'] as String?,
      endedReason: data['endedReason'] as String?,
    );
  }

  /// Fields a parent edits (status/progress bookkeeping is written by
  /// [MilestoneService] and the approval transaction).
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'illustration': illustration,
      'rewardTitle': rewardTitle,
      'rewardIcon': rewardIcon,
      'startsAt': Timestamp.fromDate(startsAt),
      'endsAt': Timestamp.fromDate(endsAt),
      'boardLength': boardLength,
      'spacesPerTask': spacesPerTask,
      'eligibility': eligibility.toMap(),
      'participantIds': participantIds,
      'status': status.name,
      'position': position,
    };
  }
}

/// One approved task's move on a milestone board. Document id = the task
/// occurrence id, so a task can never contribute twice. Create-only.
class MilestoneContribution {
  const MilestoneContribution({
    required this.taskId,
    required this.childId,
    required this.spaces,
    required this.fromPosition,
    required this.toPosition,
    required this.approvedAt,
    this.taskTitle = '',
    this.scheduleId,
    this.completedAt,
    this.approvedBy,
  });

  final String taskId;
  final String childId;
  final String taskTitle;
  final String? scheduleId;

  /// Spaces actually applied (can be less than `spacesPerTask` at the end).
  final int spaces;
  final int fromPosition;
  final int toPosition;
  final DateTime? completedAt;
  final DateTime approvedAt;
  final String? approvedBy;

  factory MilestoneContribution.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MilestoneContribution(
      taskId: doc.id,
      childId: data['childId'] as String? ?? '',
      taskTitle: data['taskTitle'] as String? ?? '',
      scheduleId: data['scheduleId'] as String?,
      spaces: data['spaces'] as int? ?? 0,
      fromPosition: data['fromPosition'] as int? ?? 0,
      toPosition: data['toPosition'] as int? ?? 0,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      approvedBy: data['approvedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'childId': childId,
      'taskTitle': taskTitle,
      'scheduleId': scheduleId,
      'spaces': spaces,
      'fromPosition': fromPosition,
      'toPosition': toPosition,
      'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      'approvedAt': Timestamp.fromDate(approvedAt),
      'approvedBy': approvedBy,
    };
  }
}
