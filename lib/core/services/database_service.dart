import 'dart:async';

import 'package:famotive/core/models/goal.dart';
import 'package:famotive/core/models/goal_contribution.dart';
import 'package:famotive/core/services/goal_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/household.dart';
import '../models/join_request.dart';
import '../models/redemption.dart';
import '../models/reward.dart';
import '../models/task.dart';
import '../models/task_proof.dart';
import '../models/task_schedule.dart';
import '../models/user.dart';
import 'time_zone_service.dart';

/// Firestore-backed household data: the households the signed-in user
/// belongs to, and for the active one its members, join requests, tasks,
/// rewards and redemptions, kept in sync via live listeners.
class DatabaseService extends ChangeNotifier {
  DatabaseService({
    FirebaseFirestore? firestore,
    Future<String?> Function()? deviceTimeZone,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _deviceTimeZone = deviceTimeZone ?? TimeZoneService.localTimeZone;

  final FirebaseFirestore _firestore;
  final Future<String?> Function() _deviceTimeZone;

  /// Household we've already tried to fill in a missing time zone for.
  String? _timeZoneBackfilledFor;

  String? _householdId;

  /// The signed-in user (see [bindSession]); null in some tests.
  AppUser? _sessionUser;

  /// Called when the active household isn't (or is no longer) one of
  /// [myHouseholds] - e.g. the user was removed - with the household to
  /// switch to instead (null: none left). Wired to AuthService.switchHousehold.
  void Function(String? householdId)? onActiveHouseholdMissing;

  /// Called when a pending join request was answered: approved (the user is
  /// now a member) or declined/withdrawn. Wired to
  /// AuthService.forgetPendingHousehold.
  void Function(String householdId, {required bool approved})?
  onPendingRequestResolved;

  /// Every household the signed-in user is a member of, by name.
  List<Household> myHouseholds = [];

  /// False until the first [myHouseholds] snapshot arrives.
  bool membershipsLoaded = false;

  /// The signed-in user's own join requests still waiting for an admin.
  List<JoinRequest> myPendingRequests = [];

  /// People asking to join the active household (the admin approves).
  List<JoinRequest> joinRequests = [];

  Household? household;
  List<AppUser> familyMembers = [];
  List<TaskModel> tasks = [];

  /// Repeating tasks (the rules; their occurrences are in [tasks]).
  List<TaskSchedule> schedules = [];
  List<Reward> availableRewards = [];

  /// Every redemption ever recorded for this household, newest first.
  List<Redemption> redemptions = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myHouseholdsSub;
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
  _pendingSubs = {};
  final Map<String, JoinRequest> _pendingById = {};
  String? _sessionUserId;
  String? _pendingUserId;
  final Set<String> _pendingMissing = {};
  String? _lastMissingRequest;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _householdSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _joinRequestsSub;
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
  _memberSubs = {};
  final Map<String, AppUser> _membersById = {};
  bool _ownerBackfillTried = false;
  bool _purgeTried = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tasksSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _schedulesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rewardsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _redemptionsSub;

  /// Binds everything for the signed-in [user] (null: logged out): their
  /// household memberships, their pending join requests and their active
  /// household's data.
  void bindSession(AppUser? user) {
    _sessionUser = user;
    _bindMemberships(user?.id);
    _bindPendingRequests(user);
    bindHousehold(user?.householdId);
    _checkActiveHousehold();
    _checkPendingResolved();
  }

  void _bindMemberships(String? userId) {
    if (userId == _sessionUserId) return;
    _sessionUserId = userId;
    unawaited(_myHouseholdsSub?.cancel());
    _myHouseholdsSub = null;
    myHouseholds = [];
    membershipsLoaded = false;
    _lastMissingRequest = null;
    if (userId == null) return;

    _myHouseholdsSub = _firestore
        .collection('households')
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .listen((snap) {
          myHouseholds = snap.docs.map(Household.fromFirestore).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          membershipsLoaded = true;
          notifyListeners();
          _checkActiveHousehold();
          _checkPendingResolved();
        }, onError: _logError('memberships'));
  }

  /// Active household missing from [myHouseholds] (removed, left, or never
  /// set): ask to switch to another one.
  void _checkActiveHousehold() {
    final user = _sessionUser;
    if (user == null || !membershipsLoaded) return;
    final active = user.householdId;
    final ids = myHouseholds.map((h) => h.id).toList();
    if (active != null && ids.contains(active)) {
      _lastMissingRequest = null;
      return;
    }
    final fallback = ids.isEmpty ? null : ids.first;
    if (fallback == active) return;
    final key = '$active->$fallback';
    if (_lastMissingRequest == key) return;
    _lastMissingRequest = key;
    onActiveHouseholdMissing?.call(fallback);
  }

  void _bindPendingRequests(AppUser? user) {
    final wanted = {...?user?.pendingHouseholdIds};
    final sameUser = _pendingUserId == user?.id;
    _pendingUserId = user?.id;
    var changed = false;
    for (final id in _pendingSubs.keys.toList()) {
      if (!wanted.contains(id) || !sameUser) {
        unawaited(_pendingSubs.remove(id)?.cancel());
        _pendingById.remove(id);
        _pendingMissing.remove(id);
        changed = true;
      }
    }
    if (user == null) {
      myPendingRequests = [];
      return;
    }
    for (final householdId in wanted) {
      if (_pendingSubs.containsKey(householdId)) continue;
      changed = true;
      _pendingSubs[householdId] = _firestore
          .collection('households')
          .doc(householdId)
          .collection('joinRequests')
          .doc(user.id)
          .snapshots()
          .listen((snap) {
            if (snap.exists) {
              _pendingById[householdId] = JoinRequest.fromFirestore(snap);
              _pendingMissing.remove(householdId);
            } else {
              // Gone: approved (then we're a member) or declined.
              _pendingById.remove(householdId);
              _pendingMissing.add(householdId);
            }
            _publishPending();
            _checkPendingResolved();
          }, onError: _logError('join request $householdId'));
    }
    if (changed) _publishPending();
  }

  void _publishPending() {
    myPendingRequests = _pendingById.values.toList()
      ..sort(
        (a, b) => (a.householdName ?? '').compareTo(b.householdName ?? ''),
      );
    notifyListeners();
  }

  /// A pending household we've since become a member of was approved; one
  /// whose request disappeared without that was declined.
  void _checkPendingResolved() {
    final user = _sessionUser;
    if (user == null || !membershipsLoaded) return;
    for (final id in user.pendingHouseholdIds) {
      if (myHouseholds.any((h) => h.id == id)) {
        onPendingRequestResolved?.call(id, approved: true);
      } else if (_pendingMissing.contains(id)) {
        onPendingRequestResolved?.call(id, approved: false);
      }
    }
  }

  void Function(Object) _logError(String what) =>
      (Object e) => debugPrint('DatabaseService: $what listener error: $e');

  /// (Re)binds to the given household; null (e.g. logout) clears all data.
  void bindHousehold(String? householdId) {
    if (householdId == _householdId) return;
    _householdId = householdId;
    _ownerBackfillTried = false;
    _purgeTried = false;

    unawaited(_householdSub?.cancel());
    unawaited(_joinRequestsSub?.cancel());
    _cancelMemberSubs();
    unawaited(_tasksSub?.cancel());
    unawaited(_schedulesSub?.cancel());
    unawaited(_rewardsSub?.cancel());
    unawaited(_redemptionsSub?.cancel());

    household = null;
    familyMembers = [];
    joinRequests = [];
    tasks = [];
    schedules = [];
    availableRewards = [];
    redemptions = [];
    notifyListeners();

    if (householdId == null) return;

    final householdRef = _firestore.collection('households').doc(householdId);

    _householdSub = householdRef.snapshots().listen((snap) {
      household = snap.exists ? Household.fromFirestore(snap) : null;
      final h = household;
      _syncMemberSubs(h?.memberIds ?? const []);
      notifyListeners();
      if (h != null && h.timezone == null) unawaited(_backfillTimeZone(h.id));
      if (h != null && h.ownerId == null) unawaited(_backfillOwner(h));
    }, onError: _logError('household'));

    _joinRequestsSub = householdRef
        .collection('joinRequests')
        .snapshots()
        .listen((snap) {
          joinRequests = snap.docs.map(JoinRequest.fromFirestore).toList()
            ..sort(
              (a, b) => (a.requestedAt ?? DateTime(0)).compareTo(
                b.requestedAt ?? DateTime(0),
              ),
            );
          notifyListeners();
        }, onError: _logError('join requests'));

    _tasksSub = householdRef.collection('tasks').snapshots().listen((snap) {
      tasks = snap.docs.map(TaskModel.fromFirestore).toList();
      notifyListeners();
      unawaited(_purgeExpiredTasks());
    }, onError: _logError('tasks'));

    _schedulesSub = householdRef.collection('taskSchedules').snapshots().listen(
      (snap) {
        schedules =
            snap.docs
                .map(TaskSchedule.fromFirestore)
                .whereType<TaskSchedule>()
                .toList()
              ..sort(
                (a, b) =>
                    a.title.toLowerCase().compareTo(b.title.toLowerCase()),
              );
        notifyListeners();
      },
    );

    _rewardsSub = householdRef.collection('rewards').snapshots().listen((snap) {
      availableRewards = snap.docs.map(Reward.fromFirestore).toList();
      notifyListeners();
    }, onError: _logError('rewards'));

    _redemptionsSub = householdRef.collection('redemptions').snapshots().listen(
      (snap) {
        final list = snap.docs.map(Redemption.fromFirestore).toList();
        list.sort((a, b) => b.redeemedAt.compareTo(a.redeemedAt));
        redemptions = list;
        notifyListeners();
      },
      onError: _logError('redemptions'),
    );
  }

  /// One live listener per member profile (read by id: Firestore rules check
  /// each against the household's memberIds), kept in memberIds order.
  void _syncMemberSubs(List<String> memberIds) {
    for (final id in _memberSubs.keys.toList()) {
      if (!memberIds.contains(id)) {
        unawaited(_memberSubs.remove(id)?.cancel());
        _membersById.remove(id);
      }
    }
    for (final id in memberIds) {
      if (_memberSubs.containsKey(id)) continue;
      _memberSubs[id] = _firestore
          .collection('users')
          .doc(id)
          .snapshots()
          .listen((snap) {
            if (snap.exists) {
              _membersById[id] = AppUser.fromFirestore(snap);
            } else {
              _membersById.remove(id);
            }
            _publishMembers();
          }, onError: _logError('member $id'));
    }
    _publishMembers();
  }

  void _publishMembers() {
    final order = household?.memberIds ?? const <String>[];
    familyMembers = [
      for (final id in order)
        if (_membersById[id] != null) _membersById[id]!,
    ];
    notifyListeners();
  }

  void _cancelMemberSubs() {
    for (final sub in _memberSubs.values) {
      unawaited(sub.cancel());
    }
    _memberSubs.clear();
    _membersById.clear();
  }

  /// Households from before admins existed: their first member (who
  /// created it) becomes the admin. Done by a parent's device.
  Future<void> _backfillOwner(Household h) async {
    final user = _sessionUser;
    if (_ownerBackfillTried ||
        user == null ||
        !user.isParent ||
        h.memberIds.isEmpty) {
      return;
    }
    _ownerBackfillTried = true;
    try {
      await _firestore.collection('households').doc(h.id).update({
        'ownerId': h.memberIds.first,
      });
    } catch (e) {
      debugPrint('DatabaseService: could not set household admin: $e');
    }
  }

  /// Data privacy: tasks older than [AppConstants.taskDeleteAfterDays] are
  /// deleted. The server does this every morning; a parent's device also
  /// sweeps once per household it opens, in case the server hasn't yet.
  Future<void> _purgeExpiredTasks() async {
    final user = _sessionUser;
    if (_purgeTried || user == null || !user.isParent) return;
    _purgeTried = true;
    final expired = tasks.where((t) => t.isAgedOut).map((t) => t.id).toList();
    if (expired.isEmpty) return;
    try {
      for (var i = 0; i < expired.length; i += 400) {
        final batch = _firestore.batch();
        for (final id in expired.skip(i).take(400)) {
          batch.delete(_tasksCollection.doc(id));
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('DatabaseService: could not delete expired tasks: $e');
    }
  }

  @override
  void dispose() {
    _myHouseholdsSub?.cancel();
    for (final sub in _pendingSubs.values) {
      sub.cancel();
    }
    _householdSub?.cancel();
    _joinRequestsSub?.cancel();
    _cancelMemberSubs();
    _tasksSub?.cancel();
    _schedulesSub?.cancel();
    _rewardsSub?.cancel();
    _redemptionsSub?.cancel();
    super.dispose();
  }

  /// Households created before time zones existed get this device's zone
  /// (once per binding), which starts their 9 AM reminders.
  Future<void> _backfillTimeZone(String householdId) async {
    if (_timeZoneBackfilledFor == householdId) return;
    _timeZoneBackfilledFor = householdId;
    final tz = await _deviceTimeZone();
    if (tz == null || householdId != _householdId) return;
    try {
      await _firestore.collection('households').doc(householdId).update({
        'timezone': tz,
      });
    } catch (e) {
      debugPrint('DatabaseService: could not set household time zone: $e');
    }
  }

  // --- Queries ---------------------------------------------------------

  String? get activeHouseholdId => _householdId;

  /// Premium features (photo proof) are on in the active household: its
  /// admin has Famotive Premium.
  bool get householdHasPremium => household?.hasPremium ?? false;

  /// Whether finishing [task] needs a photo right now. A task can ask for
  /// photo proof, but it only applies while the household has Premium
  /// (the Firestore rules agree: without Premium it can be finished without
  /// one).
  bool needsPhoto(TaskModel task) => task.requiresPhoto && householdHasPremium;

  List<AppUser> get children =>
      familyMembers.where((m) => m.isChild).toList(growable: false);

  /// Parents / other adults in the active household.
  List<AppUser> get adults =>
      familyMembers.where((m) => m.isParent).toList(growable: false);

  /// Whether the signed-in user is the active household's admin.
  bool get isAdmin => household?.isAdmin(_sessionUser?.id) ?? false;

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

  /// Tasks that aren't archived ([TaskModel.isArchived]), aren't a
  /// repeating task's not-yet-due occurrence ([TaskModel.isUpcoming]), and
  /// weren't approved more than a week ago ([TaskModel.isStaleDone]).
  List<TaskModel> get activeTasks => tasks
      .where((t) => !t.isArchived && !t.isUpcoming && !t.isStaleDone)
      .toList(growable: false);

  /// Manually archived tasks (aged-out ones are on their way to deletion
  /// and not shown at all).
  List<TaskModel> get archivedTasks =>
      tasks.where((t) => t.archived && !t.isAgedOut).toList(growable: false);

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

  /// A task that changes hands starts over as a fresh to-do: otherwise a
  /// task completed by one child and moved back to the household pool would
  /// show up as "awaiting approval" again as soon as someone claimed it.
  static Map<String, dynamic> _freshAssignment(String? childId) => {
        'assignedToUserId': childId,
        'status': TaskStatus.pending.name,
        'completedAt': null,
        'approvedAt': null,
        'claimedBy': FieldValue.delete(),
        'proof': FieldValue.delete(),
      };

  TaskModel? taskById(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Changes who a task is assigned to; null clears it back to the pool.
  /// The task goes back to "to do" (see [_freshAssignment]).
  Future<void> reassignTask(String taskId, String? childId) async {
    await _tasksCollection.doc(taskId).update(_freshAssignment(childId));
  }

  /// Overwrites every editable field of an existing task. If the assignee
  /// changed, the task goes back to "to do" (see [reassignTask]).
  Future<void> updateTask(String taskId, TaskModel task) async {
    final ref = _tasksCollection.doc(taskId);
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final before = snap.exists ? TaskModel.fromFirestore(snap) : null;
      final reassigned =
          before != null && before.assignedToUserId != task.assignedToUserId;
      transaction.update(ref, {
        ...task.toFirestore(),
        if (reassigned) ..._freshAssignment(task.assignedToUserId),
      });
    });
  }

  // --- Mutations: repeating tasks ----------------------------------------

  CollectionReference<Map<String, dynamic>> get _schedulesCollection =>
      _firestore
          .collection('households')
          .doc(_householdId)
          .collection('taskSchedules');

  /// Creates a repeating task. The server generates its occurrences.
  Future<String> addSchedule(TaskSchedule schedule) async {
    final ref = await _schedulesCollection.add(schedule.toFirestore());
    return ref.id;
  }

  /// Edits a repeating task. Occurrences after today that haven't been
  /// started are regenerated by the server; today's is left alone.
  Future<void> updateSchedule(String scheduleId, TaskSchedule schedule) async {
    await _schedulesCollection.doc(scheduleId).update(schedule.toFirestore());
  }

  /// Stops a repeating task. Already-created occurrences up to today stay.
  Future<void> deleteSchedule(String scheduleId) async {
    await _schedulesCollection.doc(scheduleId).delete();
  }

  TaskSchedule? scheduleById(String? id) {
    if (id == null) return null;
    for (final s in schedules) {
      if (s.id == id) return s;
    }
    return null;
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
      'completedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> submitTaskProof(
    String taskId, {
    required String photoPath,
    required TaskScanResult scan,
    DateTime? now,
  }) async {
    final taskRef = _tasksCollection.doc(taskId);
    final at = now ?? DateTime.now();
    final proof = TaskProof(
      photoPath: photoPath,
      submittedAt: at,
      deleteAt: at.add(const Duration(days: AppConstants.taskPhotoRetentionDays)),
      scan: scan,
    );
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(taskRef);
      if (!snap.exists) throw Exception('This task no longer exists.');
      final task = TaskModel.fromFirestore(snap);
      if (task.status != TaskStatus.pending) {
        throw Exception('This task was already marked done.');
      }
      transaction.update(taskRef, {
        'status': TaskStatus.completed.name,
        'completedAt': Timestamp.fromDate(at),
        'proof': proof.toMap(),
      });
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

      transaction.update(taskRef, {
        'status': TaskStatus.pending.name,
        'completedAt': null,
        'proof': FieldValue.delete(),
      });
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

      // `claimedBy` lets the push-notification Cloud Function tell a child
      // claiming a task ("accepted", notify parents) apart from a parent
      // assigning it (notify the child).
      // A pool task is always claimed as a fresh to-do.
      transaction.update(taskRef, {
        'assignedToUserId': childId,
        'claimedBy': childId,
        'status': TaskStatus.pending.name,
        'completedAt': null,
        'approvedAt': null,
        'proof': FieldValue.delete(),
      });
    });
  }

  /// Parent approves a completed task: grants XP and coins to the child.
  Future<void> approveTask(String taskId) =>
      _finishTask(taskId, from: const {TaskStatus.completed});

  /// Parent marks a task done themselves.
  Future<void> parentCompleteTask(String taskId) =>
      _finishTask(taskId, from: const {TaskStatus.pending, TaskStatus.completed});

  /// Moves a task whose status is in [from] to `approved` and grants its
  /// rewards to the assigned child, all in one transaction so rewards are
  /// granted at most once.
  Future<void> _finishTask(String taskId, {required Set<TaskStatus> from}) async {
    final taskRef = _tasksCollection.doc(taskId);

    final approvedTask = await _firestore.runTransaction<TaskModel?>((
      transaction,
    ) async {
      // All reads must happen before any writes in a transaction.
      final taskSnap = await transaction.get(taskRef);
      if (!taskSnap.exists) return null;

      final task = TaskModel.fromFirestore(taskSnap);

      if (!from.contains(task.status)) return;

      final now = Timestamp.fromDate(DateTime.now());
      final approval = <String, Object?>{
        'status': TaskStatus.approved.name,
        'approvedAt': now,
        if (task.status == TaskStatus.pending) 'completedAt': now,
        if (task.proof?.verdict.needsReview ?? false) 'proof.parentOverride': true,
      };

      final assignedTo = task.assignedToUserId;

      if (assignedTo == null) {
        transaction.update(taskRef, approval);
        return task;
      }

      // XP and coins live on the child's account, so they count in every
      // household the child belongs to.
      final userRef = _firestore.collection('users').doc(assignedTo);
      final userSnap = await transaction.get(userRef);

      transaction.update(taskRef, approval);

      if (userSnap.exists) {
        final currentXp = userSnap.data()?['xp'] as int? ?? 0;
        final currentCoins = userSnap.data()?['coins'] as int? ?? 0;

        transaction.update(userRef, {
          'xp': currentXp + task.rewardXp,
          'coins': currentCoins + task.coinReward,
        });
      }

      return task;
    });

    if (approvedTask == null) return;

    await _recordTaskApprovalGoalProgress(taskId: taskId, task: approvedTask);
  }

  Future<void> _recordTaskApprovalGoalProgress({
    required String taskId,
    required TaskModel task,
  }) async {
    final householdId = _householdId;
    final userId = task.assignedToUserId;

    if (householdId == null || userId == null) return;

    final now = DateTime.now();

    final goalsSnapshot = await _firestore
        .collection('households')
        .doc(householdId)
        .collection('goals')
        .get();

    final goalService = GoalService(firestore: _firestore);

    for (final goalDoc in goalsSnapshot.docs) {
      final goal = Goal.fromFirestore(goalDoc);

      final amount = switch (goal.metric) {
        GoalMetric.tasksCompleted => 1,
        GoalMetric.xpEarned => task.rewardXp,
        GoalMetric.coinsEarned => task.coinReward,
      };

      await goalService.recordContribution(
        householdId: householdId,
        goalId: goal.id,
        contribution: GoalContribution(
          activityId: taskId,
          userId: userId,
          amount: amount,
          activityType: GoalActivityType.taskApproval,
          recordedAt: now,
        ),
      );
    }
  }

  // --- Mutations: household membership ---------------------------------------

  DocumentReference<Map<String, dynamic>> get _householdRef =>
      _firestore.collection('households').doc(_householdId);

  /// Admin lets [request]'s user in (adds them to memberIds) and clears the
  /// request.
  Future<void> approveJoinRequest(JoinRequest request) async {
    final batch = _firestore.batch();
    batch.update(_householdRef, {
      'memberIds': FieldValue.arrayUnion([request.userId]),
    });
    batch.delete(_householdRef.collection('joinRequests').doc(request.userId));
    await batch.commit();
  }

  /// Admin turns a join request down.
  Future<void> declineJoinRequest(JoinRequest request) async {
    await _householdRef.collection('joinRequests').doc(request.userId).delete();
  }

  /// Removes [userId] from the active household. Their unfinished tasks
  /// here go back to the household pool; their XP and coins stay with them.
  Future<void> removeMember(String userId) async {
    final h = household;
    if (h == null) return;
    if (h.ownerId == userId) {
      throw Exception(
        'The admin can\'t be removed. Make someone else admin first.',
      );
    }
    final unfinished = tasks.where(
      (t) => t.assignedToUserId == userId && t.status != TaskStatus.approved,
    );
    final batch = _firestore.batch();
    for (final task in unfinished) {
      batch.update(_tasksCollection.doc(task.id), _freshAssignment(null));
    }
    await batch.commit();
    await _householdRef.update({
      'memberIds': FieldValue.arrayRemove([userId]),
    });
  }

  /// Admin hands the admin role to another parent in the household.
  Future<void> transferAdmin(String userId) async {
    final member = userById(userId);
    if (member == null || !member.isParent) {
      throw Exception('Only a parent in this household can be made admin.');
    }
    await _householdRef.update({'ownerId': userId});
  }

  Future<void> renameHousehold(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _householdRef.update({'name': trimmed});
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
