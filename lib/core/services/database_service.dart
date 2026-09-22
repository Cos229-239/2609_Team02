import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/household.dart';
import '../models/redemption.dart';
import '../models/reward.dart';
import '../models/task.dart';
import '../models/user.dart';

/// Firestore-backed household data: family members, tasks, rewards and
/// redemptions, kept in sync via live listeners.
class DatabaseService extends ChangeNotifier {
  DatabaseService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  String? _householdId;

  Household? household;
  List<AppUser> familyMembers = [];
  List<TaskModel> tasks = [];
  List<Reward> availableRewards = [];

  /// Every redemption ever recorded for this household, newest first.
  List<Redemption> redemptions = [];

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _householdSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tasksSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rewardsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _redemptionsSub;

  /// (Re)binds to the given household; null (e.g. logout) clears all data.
  void bindHousehold(String? householdId) {
    if (householdId == _householdId) return;
    _householdId = householdId;

    unawaited(_householdSub?.cancel());
    unawaited(_membersSub?.cancel());
    unawaited(_tasksSub?.cancel());
    unawaited(_rewardsSub?.cancel());
    unawaited(_redemptionsSub?.cancel());

    household = null;
    familyMembers = [];
    tasks = [];
    availableRewards = [];
    redemptions = [];
    notifyListeners();

    if (householdId == null) return;

    final householdRef = _firestore.collection('households').doc(householdId);

    _householdSub = householdRef.snapshots().listen((snap) {
      household = snap.exists ? Household.fromFirestore(snap) : null;
      notifyListeners();
    });

    _membersSub = _firestore
        .collection('users')
        .where('householdId', isEqualTo: householdId)
        .snapshots()
        .listen((snap) {
          familyMembers = snap.docs.map(AppUser.fromFirestore).toList();
          notifyListeners();
        });

    _tasksSub = householdRef.collection('tasks').snapshots().listen((snap) {
      tasks = snap.docs.map(TaskModel.fromFirestore).toList();
      notifyListeners();
    });

    _rewardsSub = householdRef.collection('rewards').snapshots().listen((snap) {
      availableRewards = snap.docs.map(Reward.fromFirestore).toList();
      notifyListeners();
    });

    _redemptionsSub = householdRef
        .collection('redemptions')
        .snapshots()
        .listen((snap) {
          final list = snap.docs.map(Redemption.fromFirestore).toList();
          list.sort((a, b) => b.redeemedAt.compareTo(a.redeemedAt));
          redemptions = list;
          notifyListeners();
        });
  }

  @override
  void dispose() {
    _householdSub?.cancel();
    _membersSub?.cancel();
    _tasksSub?.cancel();
    _rewardsSub?.cancel();
    _redemptionsSub?.cancel();
    super.dispose();
  }

  // --- Queries ---------------------------------------------------------

  List<AppUser> get children =>
      familyMembers.where((m) => m.isChild).toList(growable: false);

  AppUser? userById(String id) {
    for (final member in familyMembers) {
      if (member.id == id) return member;
    }
    return null;
  }

  /// Looks up a reward by id, or null if it no longer exists.
  Reward? rewardById(String id) {
    for (final reward in availableRewards) {
      if (reward.id == id) return reward;
    }
    return null;
  }

  /// Tasks that aren't archived: see [TaskModel.isArchived].
  List<TaskModel> get activeTasks =>
      tasks.where((t) => !t.isArchived).toList(growable: false);

  /// Manually archived or aged-out tasks.
  List<TaskModel> get archivedTasks =>
      tasks.where((t) => t.isArchived).toList(growable: false);

  List<TaskModel> tasksForUser(String userId) => activeTasks
      .where((t) => t.assignedToUserId == userId)
      .toList(growable: false);

  /// Unclaimed tasks in the household's shared pool.
  List<TaskModel> get availableTasks =>
      activeTasks.where((t) => t.isAvailable).toList(growable: false);

  /// Redemptions a parent hasn't seen yet.
  List<Redemption> get unacknowledgedRedemptions =>
      redemptions.where((r) => !r.acknowledgedByParent).toList(growable: false);

  List<Redemption> redemptionsForChild(String childId) =>
      redemptions.where((r) => r.childId == childId).toList(growable: false);

  // --- Mutations: tasks --------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _tasksCollection =>
      _firestore.collection('households').doc(_householdId).collection('tasks');

  CollectionReference<Map<String, dynamic>> get _rewardsCollection => _firestore
      .collection('households')
      .doc(_householdId)
      .collection('rewards');

  CollectionReference<Map<String, dynamic>> get _redemptionsCollection =>
      _firestore
          .collection('households')
          .doc(_householdId)
          .collection('redemptions');

  /// Adds a new task and returns its Firestore id.
  Future<String> addTask(TaskModel task) async {
    final ref = await _tasksCollection.add(task.toFirestore());
    return ref.id;
  }

  /// Changes who a task is assigned to; null clears it back to the pool.
  Future<void> reassignTask(String taskId, String? childId) async {
    await _tasksCollection.doc(taskId).update({'assignedToUserId': childId});
  }

  /// Overwrites every editable field of an existing task.
  Future<void> updateTask(String taskId, TaskModel task) async {
    await _tasksCollection.doc(taskId).update(task.toFirestore());
  }

  /// Permanently removes a task (parent-only action from the edit screen).
  Future<void> removeTask(String taskId) async {
    await _tasksCollection.doc(taskId).delete();
  }

  /// Manually archives/unarchives a task, independent of its age: see
  /// [TaskModel.archived].
  Future<void> setTaskArchived(String taskId, bool archived) async {
    await _tasksCollection.doc(taskId).update({'archived': archived});
  }

  /// Child marks a task done: moves it to `completed`, awaiting approval.
  Future<void> completeTask(String taskId) async {
    await _tasksCollection.doc(taskId).update({
      'status': TaskStatus.completed.name,
    });
  }

  Future<void> uncompleteTask(String taskId) async {
    final taskRef = _tasksCollection.doc(taskId);

    await _firestore.runTransaction((transaction) async {
      final taskSnap = await transaction.get(taskRef);
      if (!taskSnap.exists) return;

      final task = TaskModel.fromFirestore(taskSnap);

      // Only tasks awaiting approval can be marked incomplete again.
      if (task.status != TaskStatus.completed) return;

      transaction.update(taskRef, {'status': TaskStatus.pending.name});
    });
  }

  /// Child claims an unassigned task from the shared pool.
  Future<void> claimTask(String taskId, String childId) async {
    final taskRef = _tasksCollection.doc(taskId);

    await _firestore.runTransaction((transaction) async {
      final taskSnap = await transaction.get(taskRef);
      if (!taskSnap.exists) return;

      final task = TaskModel.fromFirestore(taskSnap);

      // Prevent an already-claimed task from being reassigned to another child.
      if (task.assignedToUserId != null) return;

      transaction.update(taskRef, {'assignedToUserId': childId});
    });
  }

  /// Parent approves a completed task: grants XP and coins to the child.
  Future<void> approveTask(String taskId) async {
    final taskRef = _tasksCollection.doc(taskId);
    await _firestore.runTransaction((transaction) async {
      // All reads must happen before any writes in a transaction.
      final taskSnap = await transaction.get(taskRef);
      if (!taskSnap.exists) return;
      final task = TaskModel.fromFirestore(taskSnap);

      if (task.status != TaskStatus.completed) return;

      final assignedTo = task.assignedToUserId;
      if (assignedTo == null) {
        transaction.update(taskRef, {'status': TaskStatus.approved.name});
        return;
      }

      final userRef = _firestore.collection('users').doc(assignedTo);
      final userSnap = await transaction.get(userRef);

      transaction.update(taskRef, {'status': TaskStatus.approved.name});
      if (userSnap.exists) {
        final currentXp = userSnap.data()?['xp'] as int? ?? 0;
        final currentCoins = userSnap.data()?['coins'] as int? ?? 0;
        transaction.update(userRef, {
          'xp': currentXp + task.rewardXp,
          'coins': currentCoins + task.coinReward,
        });
      }
    });
  }

  // --- Mutations: reward store --------------------------------------------

  Future<void> addReward(Reward reward) async {
    await _rewardsCollection.add(reward.toFirestore());
  }

  Future<void> updateReward(String rewardId, Reward reward) async {
    await _rewardsCollection.doc(rewardId).update(reward.toFirestore());
  }

  Future<void> deleteReward(String rewardId) async {
    await _rewardsCollection.doc(rewardId).delete();
  }

  /// Deducts coins and records a [Redemption] atomically. Throws if the
  /// reward no longer exists or the child can't afford it.
  Future<void> redeemReward({
    required String rewardId,
    required String childId,
  }) async {
    final rewardRef = _rewardsCollection.doc(rewardId);
    final userRef = _firestore.collection('users').doc(childId);
    final redemptionRef = _redemptionsCollection.doc();

    await _firestore.runTransaction((transaction) async {
      final rewardSnap = await transaction.get(rewardRef);
      final userSnap = await transaction.get(userRef);

      if (!rewardSnap.exists) {
        throw Exception('This reward is no longer available.');
      }
      if (!userSnap.exists) {
        throw Exception('Could not find your profile.');
      }

      final reward = Reward.fromFirestore(rewardSnap);
      final currentCoins = userSnap.data()?['coins'] as int? ?? 0;

      if (currentCoins < reward.coinCost) {
        throw Exception('Not enough coins yet - keep completing tasks!');
      }

      transaction.update(userRef, {'coins': currentCoins - reward.coinCost});
      transaction.set(redemptionRef, {
        'rewardId': rewardId,
        'rewardTitle': reward.title,
        'rewardIcon': reward.icon,
        'childId': childId,
        'coinCost': reward.coinCost,
        'redeemedAt': Timestamp.fromDate(DateTime.now()),
        'acknowledgedByParent': false,
      });
    });
  }

  /// Sets (or clears, with null) the reward a child has pinned as a goal.
  Future<void> setPinnedReward(String childId, String? rewardId) async {
    await _firestore.collection('users').doc(childId).update({
      'pinnedRewardId': rewardId,
    });
  }

  /// Marks a redemption as seen by a parent.
  Future<void> acknowledgeRedemption(String redemptionId) async {
    await _redemptionsCollection.doc(redemptionId).update({
      'acknowledgedByParent': true,
    });
  }

  /// Marks every unacknowledged redemption as seen.
  Future<void> acknowledgeAllRedemptions() async {
    final pending = unacknowledgedRedemptions;
    if (pending.isEmpty) return;

    final batch = _firestore.batch();
    for (final redemption in pending) {
      batch.update(_redemptionsCollection.doc(redemption.id), {
        'acknowledgedByParent': true,
      });
    }
    await batch.commit();
  }
}
