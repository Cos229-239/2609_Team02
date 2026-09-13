import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/household.dart';
import '../models/reward.dart';
import '../models/task.dart';
import '../models/user.dart';

/// Firestore-backed household data: family members, tasks and rewards.
///
/// Bound to whichever household the signed-in user belongs to (see
/// [bindHousehold]) and kept in sync via live Firestore listeners, so
/// widgets that `watch` this service rebuild automatically as data
/// changes — including changes made by other family members' devices.
class DatabaseService extends ChangeNotifier {
  DatabaseService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  String? _householdId;

  Household? household;
  List<AppUser> familyMembers = [];
  List<TaskModel> tasks = [];
  List<Reward> availableRewards = [];

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _householdSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tasksSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rewardsSub;

  /// (Re)binds this service to the given household, replacing any prior
  /// Firestore listeners. Pass null (e.g. after logout) to clear all data.
  void bindHousehold(String? householdId) {
    if (householdId == _householdId) return;
    _householdId = householdId;

    unawaited(_householdSub?.cancel());
    unawaited(_membersSub?.cancel());
    unawaited(_tasksSub?.cancel());
    unawaited(_rewardsSub?.cancel());

    household = null;
    familyMembers = [];
    tasks = [];
    availableRewards = [];
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
  }

  @override
  void dispose() {
    _householdSub?.cancel();
    _membersSub?.cancel();
    _tasksSub?.cancel();
    _rewardsSub?.cancel();
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

  List<TaskModel> tasksForUser(String userId) =>
      tasks.where((t) => t.assignedToUserId == userId).toList(growable: false);

  // --- Mutations ---------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _tasksCollection => _firestore
      .collection('households')
      .doc(_householdId)
      .collection('tasks');

  Future<void> addTask(TaskModel task) async {
    await _tasksCollection.add(task.toFirestore());
  }

  Future<void> removeTask(String taskId) async {
    await _tasksCollection.doc(taskId).delete();
  }

  /// Child marks a task done — moves it to `completed`, awaiting approval.
  Future<void> completeTask(String taskId) async {
    await _tasksCollection.doc(taskId).update({
      'status': TaskStatus.completed.name,
    });
  }

  /// Parent approves a completed task — grants XP to the child.
  Future<void> approveTask(String taskId) async {
    final taskRef = _tasksCollection.doc(taskId);
    await _firestore.runTransaction((transaction) async {
      // The Flutter `cloud_firestore` transaction API requires every read
      // to happen before any write is issued, so both `get`s run up front.
      final taskSnap = await transaction.get(taskRef);
      if (!taskSnap.exists) return;
      final task = TaskModel.fromFirestore(taskSnap);

      final userRef = _firestore.collection('users').doc(task.assignedToUserId);
      final userSnap = await transaction.get(userRef);

      transaction.update(taskRef, {'status': TaskStatus.approved.name});
      if (userSnap.exists) {
        final currentXp = userSnap.data()?['xp'] as int? ?? 0;
        transaction.update(userRef, {'xp': currentXp + task.rewardXp});
      }
    });
  }
}
