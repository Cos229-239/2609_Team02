import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/family_milestone.dart';
import '../models/mini_game.dart';
import '../models/mini_game_session.dart';
import '../models/mini_game_settings.dart';
import '../models/progress_event.dart';
import '../models/task.dart';
import 'milestone_rules.dart';
import 'xp_multiplier.dart';

/// What approving one task did beyond paying its XP/coins.
class ApprovalOutcome {
  const ApprovalOutcome({
    this.milestoneId,
    this.fromPosition,
    this.toPosition,
    this.milestoneCompleted = false,
    this.miniGame,
  });

  static const none = ApprovalOutcome();

  final String? milestoneId;
  final int? fromPosition;
  final int? toPosition;
  final bool milestoneCompleted;

  /// The bonus game offered for this approval, if any.
  final MiniGameId? miniGame;

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
/// the approval itself: the family milestone contribution + board move, the
/// bonus mini-game offer, and the "show this to the child" [ProgressEvent].
///
/// Everything is keyed by the task (occurrence) id, so a retried or
/// concurrent approval can't count twice or offer two rewarded games. See
/// Documents/Family_Milestones_and_MiniGames.md.
class ApprovalEffects {
  ApprovalEffects(this._firestore, {math.Random? random, Iterable<MiniGameId>? availableGames})
    : _random = random ?? math.Random(),
      _availableGames = (availableGames ?? MiniGameId.values).toList(growable: false);

  final FirebaseFirestore _firestore;

  /// Picks the game and its seed (injectable so tests are deterministic).
  final math.Random _random;

  /// Games this build can play; only these are offered.
  final List<MiniGameId> _availableGames;

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

    // Bonus mini-game: one rewarded session per approved task, with the
    // child's settings snapshotted now.
    final settingsRef = householdRef.collection('miniGameSettings');
    final sessionRef = householdRef.collection('miniGameSessions').doc(taskId);
    final householdSettings = await transaction.get(settingsRef.doc('household'));
    final childSettings = await transaction.get(settingsRef.doc(childId));
    final sessionSnap = await transaction.get(sessionRef);
    final settings = MiniGameSettings.resolve(household: householdSettings.data(), child: childSettings.data());
    MiniGameId? game;
    if (settings.rewardedGamesEnabled && task.rewardXp > 0 && !sessionSnap.exists && _availableGames.isNotEmpty) {
      game = GameSelector.pick(settings, _random, available: _availableGames);
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

    if (game != null) {
      final offer = MiniGameSession.offer(
        childId: childId,
        taskId: taskId,
        taskTitle: task.title,
        gameId: game,
        seed: _random.nextInt(1 << 31),
        baseXp: task.rewardXp,
        settings: settings,
        now: approvedAt,
      );
      writes.add((tx) => tx.set(sessionRef, offer));
      outcome = ApprovalOutcome(
        milestoneId: outcome.milestoneId,
        fromPosition: outcome.fromPosition,
        toPosition: outcome.toPosition,
        milestoneCompleted: outcome.milestoneCompleted,
        miniGame: game,
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
      miniGameSessionId: game == null ? null : taskId,
    );
    // Only worth showing the child if the board moved or a game is waiting.
    if (event.movedBoard || game != null) {
      writes.add((tx) => tx.set(eventRef, event.toFirestore()));
    }

    return PreparedApproval._(writes, outcome);
  }
}
