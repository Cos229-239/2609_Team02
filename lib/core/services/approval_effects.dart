import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/family_milestone.dart';
import '../models/progress_event.dart';
import '../models/task.dart';
import 'milestone_rules.dart';

/// What approving one task did beyond paying its XP/coins.
class ApprovalOutcome {
  const ApprovalOutcome({this.milestoneId, this.fromPosition, this.toPosition, this.milestoneCompleted = false});

  static const none = ApprovalOutcome();

  final String? milestoneId;
  final int? fromPosition;
  final int? toPosition;
  final bool milestoneCompleted;

  bool get movedBoard => milestoneId != null;
}

/// The reads [ApprovalEffects.prepare] did inside the approval transaction,
/// ready to be written by [apply] once the caller has done its own writes'
/// reads (Firestore transactions need every read before the first write).
class PreparedApproval {
  PreparedApproval._(this._writes, this.outcome);

  static final PreparedApproval nothing = PreparedApproval._(const [], ApprovalOutcome.none);

  final List<void Function(Transaction)> _writes;
  final ApprovalOutcome outcome;

  void apply(Transaction transaction) {
    for (final write in _writes) {
      write(transaction);
    }
  }
}

/// Side effects of approving a child's task that must commit atomically with
/// the approval itself: the family milestone contribution + board move and
/// the "show this to the child" [ProgressEvent].
///
/// Everything is keyed by the task (occurrence) id, so a retried or
/// concurrent approval can't count twice. See
/// Documents/Family_Milestones_and_MiniGames.md.
class ApprovalEffects {
  ApprovalEffects(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _household(String id) =>
      _firestore.collection('households').doc(id);

  /// Outside the transaction (queries can't run inside one): milestones that
  /// may receive this approval. Re-checked inside [prepare].
  Future<List<DocumentReference<Map<String, dynamic>>>> candidateMilestones(String householdId) async {
    try {
      final snap = await _household(householdId)
          .collection('milestones')
          .where('status', isEqualTo: MilestoneStatus.active.name)
          .get();
      return [for (final doc in snap.docs) doc.reference];
    } catch (_) {
      // No milestone support (e.g. rules not deployed yet): approve anyway.
      return const [];
    }
  }

  /// Reads (only) everything the side effects need, inside [transaction].
  Future<PreparedApproval> prepare(
    Transaction transaction, {
    required String householdId,
    required String taskId,
    required TaskModel task,
    required Map<String, dynamic>? assigneeProfile,
    required DateTime approvedAt,
    required String? approverId,
    required List<DocumentReference<Map<String, dynamic>>> milestoneRefs,
  }) async {
    final childId = task.assignedToUserId;
    // Only a child's approved task moves the board / gets shown to them.
    if (childId == null || assigneeProfile == null || assigneeProfile['role'] != 'child') {
      return PreparedApproval.nothing;
    }

    final householdRef = _household(householdId);
    final eventRef = householdRef.collection('progressEvents').doc(taskId);
    final eventSnap = await transaction.get(eventRef);
    // Already handled (a retry after the approval committed elsewhere).
    if (eventSnap.exists) return PreparedApproval.nothing;

    final householdSnap = await transaction.get(householdRef);
    final memberIds = List<String>.from(
      (householdSnap.data()?['memberIds'] as List? ?? const []).whereType<String>(),
    );

    final milestones = <FamilyMilestone>[];
    for (final ref in milestoneRefs) {
      final snap = await transaction.get(ref);
      if (snap.exists) milestones.add(FamilyMilestone.fromFirestore(snap));
    }
    final current = MilestoneRules.pickCurrent(milestones);

    ContributionDecision? decision;
    DocumentReference<Map<String, dynamic>>? milestoneRef;
    DocumentReference<Map<String, dynamic>>? contributionRef;
    if (current != null) {
      milestoneRef = householdRef.collection('milestones').doc(current.id);
      contributionRef = milestoneRef.collection('contributions').doc(taskId);
      final contributionSnap = await transaction.get(contributionRef);
      decision = MilestoneRules.evaluate(
        milestone: current,
        childId: childId,
        householdMemberIds: memberIds,
        scheduleId: task.scheduleId,
        completedAt: task.completedAt,
        approvedAt: approvedAt,
        alreadyContributed: contributionSnap.exists,
      );
    }

    final writes = <void Function(Transaction)>[];
    var outcome = ApprovalOutcome.none;

    if (current != null && decision != null && decision.counts) {
      final completes = decision.to >= current.boardLength;
      final contribution = MilestoneContribution(
        taskId: taskId,
        childId: childId,
        taskTitle: task.title,
        scheduleId: task.scheduleId,
        spaces: decision.spaces,
        fromPosition: decision.from,
        toPosition: decision.to,
        completedAt: task.completedAt ?? approvedAt,
        approvedAt: approvedAt,
        approvedBy: approverId,
      );
      final mRef = milestoneRef!;
      final cRef = contributionRef!;
      writes.add((tx) {
        tx.set(cRef, contribution.toFirestore());
        tx.update(mRef, {
          'position': decision!.to,
          if (completes) 'status': MilestoneStatus.completed.name,
          if (completes) 'completedAt': Timestamp.fromDate(approvedAt),
        });
      });
      outcome = ApprovalOutcome(
        milestoneId: current.id,
        fromPosition: decision.from,
        toPosition: decision.to,
        milestoneCompleted: completes,
      );
    }

    final event = ProgressEvent(
      taskId: taskId,
      childId: childId,
      taskTitle: task.title,
      baseXp: task.rewardXp,
      createdAt: approvedAt,
      milestoneId: outcome.milestoneId,
      milestoneTitle: outcome.movedBoard ? current?.title : null,
      fromPosition: outcome.fromPosition,
      toPosition: outcome.toPosition,
      boardLength: outcome.movedBoard ? current?.boardLength : null,
      milestoneCompleted: outcome.milestoneCompleted,
    );
    // Only worth showing the child if something happened on the board.
    if (event.movedBoard) {
      writes.add((tx) => tx.set(eventRef, event.toFirestore()));
    }

    return PreparedApproval._(writes, outcome);
  }
}
