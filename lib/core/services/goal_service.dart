import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:famotive/core/models/task.dart';

import '../models/goal.dart';
import '../models/goal_contribution.dart';

/// A validated contribution ready to be written in a Firestore transaction.
class PreparedGoalContribution {
  const PreparedGoalContribution({
    required this.goalRef,
    required this.contributionRef,
    required this.contribution,
    required this.newProgress,
    required this.reachedTarget,
  });

  final DocumentReference<Map<String, dynamic>> goalRef;
  final DocumentReference<Map<String, dynamic>> contributionRef;
  final GoalContribution contribution;
  final int newProgress;
  final bool reachedTarget;

  /// Writes the contribution and updated goal progress.
  ///
  /// Call only after all required transaction reads are complete.
  void apply(Transaction transaction) {
    transaction.set(contributionRef, contribution.toFirestore());

    transaction.update(goalRef, {
      'currentProgress': newProgress,
      if (reachedTarget)
        'completedAt': Timestamp.fromDate(contribution.recordedAt),
    });
  }
}

/// Handles persistence and progress tracking for household goals.
class GoalService {
  GoalService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Validates and prepares a contribution without writing anything.
  ///
  /// This allows other services to include goal progress in their
  /// existing Firestore transactions.
  Future<PreparedGoalContribution?> prepareContribution({
    required Transaction transaction,
    required String householdId,
    required String goalId,
    required GoalContribution contribution,
    DocumentSnapshot<Map<String, dynamic>>? existingGoalSnapshot,
  }) async {
    final householdRef = _firestore.collection('households').doc(householdId);
    final goalRef = householdRef.collection('goals').doc(goalId);
    final contributionRef = goalRef
        .collection('contributions')
        .doc(contribution.activityId);

    final goalSnapshot = existingGoalSnapshot ?? await transaction.get(goalRef);

    if (!goalSnapshot.exists) return null;

    final goal = Goal.fromFirestore(goalSnapshot);

    DocumentSnapshot<Map<String, dynamic>>? householdSnapshot;

    if (goal.type == GoalType.family) {
      householdSnapshot = await transaction.get(householdRef);
    }

    if (!goal.isActiveAt(contribution.recordedAt)) return null;

    if (goal.type == GoalType.family) {
      if (householdSnapshot == null || !householdSnapshot.exists) {
        return null;
      }

      final memberIds = List<String>.from(
        householdSnapshot.data()?['memberIds'] as List? ?? const [],
      );

      if (!memberIds.contains(contribution.userId)) return null;
    } else if (!goal.participantIds.contains(contribution.userId)) {
      return null;
    }

    final contributionSnapshot = await transaction.get(contributionRef);

    if (contributionSnapshot.exists) return null;

    final calculatedProgress = goal.currentProgress + contribution.amount;

    final newProgress = calculatedProgress > goal.targetValue
        ? goal.targetValue
        : calculatedProgress;

    return PreparedGoalContribution(
      goalRef: goalRef,
      contributionRef: contributionRef,
      contribution: contribution,
      newProgress: newProgress,
      reachedTarget: newProgress >= goal.targetValue,
    );
  }

  /// Records a qualifying contribution toward a household goal.
  /// Returns true when the contribution is recorded and progress changes.
  /// Returns false when the contribution cannot be applied.
  Future<bool> recordContribution({
    required String householdId,
    required String goalId,
    required GoalContribution contribution,
  }) async {
    return _firestore.runTransaction<bool>((transaction) async {
      final prepared = await prepareContribution(
        transaction: transaction,
        householdId: householdId,
        goalId: goalId,
        contribution: contribution,
      );

      if (prepared == null) return false;

      prepared.apply(transaction);
      return true;
    });
  }

  /// Creates a challenge and links selected existing household tasks.
  ///
  /// The goal and task associations are written atomically.
  /// Returns the ID of the newly created goal.
  Future<String> createGoalWithTasks({
    required String householdId,
    required Goal goal,
    required List<String> taskIds,
    List<TaskModel> newTasks = const [],
  }) async {
    // Validate challenge details before attempting Firestore writes.
    if (goal.title.trim().isEmpty) {
      throw StateError('A challenge must have a title.');
    }

    if (goal.targetValue <= 0) {
      throw StateError('A challenge target must be greater than zero.');
    }

    if (!goal.endsAt.isAfter(goal.startsAt)) {
      throw StateError('The challenge end date must be after its start date.');
    }

    final uniqueParticipants = goal.participantIds.toSet();

    if (goal.type == GoalType.individual && uniqueParticipants.length != 1) {
      throw StateError(
        'An individual challenge must have exactly one participant.',
      );
    }

    if (goal.type == GoalType.team && uniqueParticipants.length < 2) {
      throw StateError('A team challenge must have at least two participants.');
    }

    // Each task can only appear once in a challenge creation request.
    if (taskIds.toSet().length != taskIds.length) {
      throw StateError('A task cannot be selected more than once.');
    }

    final householdRef = _firestore.collection('households').doc(householdId);
    final goalRef = householdRef.collection('goals').doc();
    final tasksCollection = householdRef.collection('tasks');

    await _firestore.runTransaction<void>((transaction) async {
      // Confirm the household exists and validate challenge participants.
      final householdSnapshot = await transaction.get(householdRef);

      if (!householdSnapshot.exists) {
        throw StateError('The household no longer exists.');
      }

      final memberIds = List<String>.from(
        householdSnapshot.data()?['memberIds'] as List? ?? const [],
      );

      for (final participantId in goal.participantIds) {
        if (!memberIds.contains(participantId)) {
          throw StateError(
            'All challenge participants must belong to the household.',
          );
        }
      }

      // Read all selected tasks before performing any writes.
      final taskSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];

      for (final taskId in taskIds) {
        final snapshot = await transaction.get(tasksCollection.doc(taskId));
        taskSnapshots.add(snapshot);
      }

      // Validate every selected task.
      for (final snapshot in taskSnapshots) {
        if (!snapshot.exists) {
          throw StateError('A selected task no longer exists.');
        }

        final task = TaskModel.fromFirestore(snapshot);

        if (task.status != TaskStatus.pending) {
          throw StateError('Only pending tasks can be added to a challenge.');
        }

        if (task.isArchived) {
          throw StateError('Archived tasks cannot be added to a challenge.');
        }

        if (task.goalId != null) {
          throw StateError(
            'A selected task already belongs to another challenge.',
          );
        }

        // Assigned tasks must belong to a member of this household.
        // Unclaimed tasks remain eligible.
        if (task.assignedToUserId != null &&
            !memberIds.contains(task.assignedToUserId)) {
          throw StateError(
            'A selected task is assigned to someone outside '
            'the household.',
          );
        }

        // Individual and team challenges can only include tasks assigned
        // to their participants. Unclaimed tasks remain eligible.
        if (goal.type != GoalType.family &&
            task.assignedToUserId != null &&
            !goal.participantIds.contains(task.assignedToUserId)) {
          throw StateError(
            'A selected task is assigned to someone outside '
            'the challenge participants.',
          );
        }
      }

      // Validate tasks created as part of this challenge.
      for (final task in newTasks) {
        if (task.title.trim().isEmpty) {
          throw StateError('A new task must have a title.');
        }

        if (task.status != TaskStatus.pending) {
          throw StateError('New challenge tasks must start as pending.');
        }

        if (task.isArchived) {
          throw StateError('Archived tasks cannot be created in a challenge.');
        }

        if (task.goalId != null) {
          throw StateError(
            'A new task cannot already belong to another challenge.',
          );
        }

        if (task.assignedToUserId != null &&
            !memberIds.contains(task.assignedToUserId)) {
          throw StateError(
            'A new task must be assigned to a household member.',
          );
        }

        if (goal.type != GoalType.family &&
            task.assignedToUserId != null &&
            !goal.participantIds.contains(task.assignedToUserId)) {
          throw StateError(
            'A new task is assigned to someone outside '
            'the challenge participants.',
          );
        }
      }
      // Queue the goal creation and all task associations together.
      transaction.set(goalRef, goal.toFirestore());

      // Associate selected existing tasks.
      for (final snapshot in taskSnapshots) {
        transaction.update(snapshot.reference, {'goalId': goalRef.id});
      }

      // Create additional tasks linked to this challenge.
      for (final task in newTasks) {
        final taskRef = tasksCollection.doc();

        transaction.set(
          taskRef,
          task.copyWith(goalId: goalRef.id).toFirestore(),
        );
      }
    });

    return goalRef.id;
  }
}
