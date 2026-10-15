import 'package:cloud_firestore/cloud_firestore.dart';

/// "Show this approval to the child": written in the same transaction that
/// approves a child's task, at `households/{householdId}/progressEvents/{taskId}`.
///
/// The child's app presents unpresented events once (board animation, then
/// the bonus game) and sets [presentedAt], so duplicate snapshots, restarts
/// and other devices never replay it.
class ProgressEvent {
  const ProgressEvent({
    required this.taskId,
    required this.childId,
    required this.createdAt,
    this.taskTitle = '',
    this.baseXp = 0,
    this.milestoneId,
    this.milestoneTitle,
    this.fromPosition,
    this.toPosition,
    this.boardLength,
    this.milestoneCompleted = false,
    this.miniGameSessionId,
    this.presentedAt,
  });

  final String taskId;
  final String childId;
  final String taskTitle;
  final int baseXp;
  final DateTime createdAt;

  /// Set when the approval moved a milestone board.
  final String? milestoneId;
  final String? milestoneTitle;
  final int? fromPosition;
  final int? toPosition;
  final int? boardLength;

  /// This approval reached the finish.
  final bool milestoneCompleted;

  /// Set when the approval offered a bonus mini-game.
  final String? miniGameSessionId;

  final DateTime? presentedAt;

  bool get movedBoard => milestoneId != null && fromPosition != null && toPosition != null;
  bool get isPresented => presentedAt != null;

  factory ProgressEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ProgressEvent(
      taskId: doc.id,
      childId: data['childId'] as String? ?? '',
      taskTitle: data['taskTitle'] as String? ?? '',
      baseXp: data['baseXp'] as int? ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      milestoneId: data['milestoneId'] as String?,
      milestoneTitle: data['milestoneTitle'] as String?,
      fromPosition: data['fromPosition'] as int?,
      toPosition: data['toPosition'] as int?,
      boardLength: data['boardLength'] as int?,
      milestoneCompleted: data['milestoneCompleted'] as bool? ?? false,
      miniGameSessionId: data['miniGameSessionId'] as String?,
      presentedAt: (data['presentedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'childId': childId,
      'taskTitle': taskTitle,
      'baseXp': baseXp,
      'createdAt': Timestamp.fromDate(createdAt),
      'milestoneId': milestoneId,
      'milestoneTitle': milestoneTitle,
      'fromPosition': fromPosition,
      'toPosition': toPosition,
      'boardLength': boardLength,
      'milestoneCompleted': milestoneCompleted,
      'miniGameSessionId': miniGameSessionId,
      // Always written (null) so "not presented yet" is queryable.
      'presentedAt': presentedAt == null ? null : Timestamp.fromDate(presentedAt!),
    };
  }
}
