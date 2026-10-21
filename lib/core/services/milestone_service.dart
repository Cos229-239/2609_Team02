import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/family_milestone.dart';
import '../models/progress_event.dart';
import '../models/user.dart';
import 'milestone_rules.dart';

/// Family milestones ("Family Goals") of the active household: live list,
/// the signed-in child's not-yet-shown progress events, and the parent
/// actions (create, edit, pause, cancel, complete, extend, restart, claim).
///
/// Board moves themselves happen in the task approval transaction (see
/// [ApprovalEffects]); this service never moves the board on its own except
/// for a parent's explicit [recalculate].
class MilestoneService extends ChangeNotifier {
  MilestoneService({FirebaseFirestore? firestore, DateTime Function()? clock})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _clock = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _clock;

  String? _householdId;
  AppUser? _user;

  /// Every milestone of the active household, newest first.
  List<FamilyMilestone> milestones = [];

  /// False until the first milestones snapshot arrives.
  bool loaded = false;

  /// Set when the milestones listener fails (offline/permissions).
  String? loadError;

  /// The signed-in child's approvals that haven't been shown yet, oldest first.
  List<ProgressEvent> unpresentedEvents = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _milestonesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _eventsSub;

  String? get householdId => _householdId;

  DocumentReference<Map<String, dynamic>> get _householdRef =>
      _firestore.collection('households').doc(_householdId);

  CollectionReference<Map<String, dynamic>> get _milestonesRef => _householdRef.collection('milestones');

  /// (Re)binds to [user]'s active household. Safe to call on every auth change.
  void bind(AppUser? user) {
    final householdId = user?.householdId;
    final sameHousehold = householdId == _householdId;
    final sameUser = user?.id == _user?.id;
    _user = user;
    if (sameHousehold && sameUser) return;

    unawaited(_milestonesSub?.cancel());
    unawaited(_eventsSub?.cancel());
    _milestonesSub = null;
    _eventsSub = null;
    _householdId = householdId;
    milestones = [];
    unpresentedEvents = [];
    loaded = false;
    loadError = null;
    notifyListeners();
    if (householdId == null || user == null) return;

    _milestonesSub = _milestonesRef.snapshots().listen(
      (snap) {
        milestones = snap.docs.map(FamilyMilestone.fromFirestore).toList()
          ..sort((a, b) => (b.createdAt ?? b.startsAt).compareTo(a.createdAt ?? a.startsAt));
        loaded = true;
        loadError = null;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('MilestoneService: milestones listener error: $e');
        loaded = true;
        loadError = 'Could not load the family goal. Check your connection.';
        notifyListeners();
      },
    );

    if (user.isChild) {
      _eventsSub = _householdRef
          .collection('progressEvents')
          .where('childId', isEqualTo: user.id)
          .where('presentedAt', isNull: true)
          .snapshots()
          .listen(
            (snap) {
              unpresentedEvents = snap.docs.map(ProgressEvent.fromFirestore).toList()
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              notifyListeners();
            },
            onError: (Object e) => debugPrint('MilestoneService: events listener error: $e'),
          );
    }
  }

  @override
  void dispose() {
    _milestonesSub?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }

  // --- Queries -------------------------------------------------------------

  /// The household's current goal (stored active/paused), if any.
  FamilyMilestone? get current => MilestoneRules.pickCurrent(milestones);

  /// What the Home card shows: the current goal, else the most recent
  /// completed one whose reward hasn't been claimed yet.
  FamilyMilestone? get featured {
    final c = current;
    if (c != null) return c;
    for (final m in milestones) {
      if (m.isCompleted && !m.isRewardClaimed) return m;
    }
    return null;
  }

  /// Finished, cancelled or replaced goals, newest first.
  List<FamilyMilestone> get history => milestones.where((m) => !m.isCurrent).toList(growable: false);

  FamilyMilestone? byId(String id) {
    for (final m in milestones) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Live contributions of one milestone, newest first.
  Stream<List<MilestoneContribution>> watchContributions(String milestoneId) {
    return _milestonesRef.doc(milestoneId).collection('contributions').snapshots().map(
          (snap) => snap.docs.map(MilestoneContribution.fromFirestore).toList()
            ..sort((a, b) => b.approvedAt.compareTo(a.approvedAt)),
        );
  }

  // --- Validation ------------------------------------------------------------

  /// User-facing problem with [m], or null if it can be saved.
  static String? validate(FamilyMilestone m, {int minBoardLength = FamilyMilestone.minBoardLength}) {
    final title = m.title.trim();
    if (title.isEmpty) return 'Give your family goal a name.';
    if (title.length > FamilyMilestone.titleMaxLength) {
      return 'Keep the name to ${FamilyMilestone.titleMaxLength} characters or fewer.';
    }
    if (m.rewardTitle.trim().isEmpty) return 'What will the family get when you reach the goal?';
    if (!m.endsAt.isAfter(m.startsAt)) return 'The deadline must be on or after the start day.';
    if (m.boardLength < minBoardLength || m.boardLength > FamilyMilestone.maxBoardLength) {
      return 'The board needs between $minBoardLength and ${FamilyMilestone.maxBoardLength} spaces.';
    }
    if (m.spacesPerTask < 1 || m.spacesPerTask > FamilyMilestone.maxSpacesPerTask) {
      return 'Each task moves 1 to ${FamilyMilestone.maxSpacesPerTask} spaces.';
    }
    if (!m.eligibility.countsAnything) return 'Choose at least one kind of task that counts.';
    return null;
  }

  // --- Parent actions ---------------------------------------------------------

  void _requireParent() {
    final user = _user;
    if (user == null || !user.isParent) {
      throw Exception('Only a parent can change the family goal.');
    }
    if (_householdId == null) throw Exception('No household selected.');
  }

  /// Creates a new current goal. Fails while another goal is current: extend,
  /// restart, replace or finish that one first.
  Future<String> create(FamilyMilestone milestone) async {
    _requireParent();
    final problem = validate(milestone);
    if (problem != null) throw Exception(problem);
    if (current != null) {
      throw Exception('Your family already has a goal in progress. Finish, cancel or replace it first.');
    }
    final ref = _milestonesRef.doc();
    await ref.set({
      ...milestone.copyWith(status: MilestoneStatus.active, position: 0).toFirestore(),
      'createdBy': _user!.id,
      'createdAt': Timestamp.fromDate(_clock()),
      'completedAt': null,
      'rewardClaimedAt': null,
    });
    return ref.id;
  }

  /// Saves a parent's edits. Progress and status are kept; the board can't be
  /// shortened below the current position.
  Future<void> update(FamilyMilestone milestone) async {
    _requireParent();
    final problem = validate(milestone, minBoardLength: _minLengthFor(milestone));
    if (problem != null) throw Exception(problem);
    final ref = _milestonesRef.doc(milestone.id);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('This goal no longer exists.');
      final stored = FamilyMilestone.fromFirestore(snap);
      if (!stored.isCurrent) throw Exception('Finished goals can\'t be edited.');
      if (milestone.boardLength < stored.position) {
        throw Exception('Your family is already on space ${stored.position} - the board can\'t be shorter than that.');
      }
      final data = milestone.toFirestore()
        ..remove('status')
        ..remove('position');
      tx.update(ref, data);
    });
  }

  int _minLengthFor(FamilyMilestone m) {
    final stored = byId(m.id);
    final min = stored?.position ?? 0;
    return min > FamilyMilestone.minBoardLength ? min : FamilyMilestone.minBoardLength;
  }

  Future<void> _transition(
    String milestoneId,
    Map<String, Object?> Function(FamilyMilestone stored) change, {
    bool Function(FamilyMilestone stored)? allowed,
    String notAllowed = 'That isn\'t possible for this goal right now.',
  }) async {
    _requireParent();
    final ref = _milestonesRef.doc(milestoneId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('This goal no longer exists.');
      final stored = FamilyMilestone.fromFirestore(snap);
      if (allowed != null && !allowed(stored)) throw Exception(notAllowed);
      tx.update(ref, change(stored));
    });
  }

  /// Stops the board moving until [resume].
  Future<void> pause(String id) => _transition(
        id,
        (_) => {'status': MilestoneStatus.paused.name},
        allowed: (m) => m.status == MilestoneStatus.active,
      );

  Future<void> resume(String id) => _transition(
        id,
        (_) => {'status': MilestoneStatus.active.name},
        allowed: (m) => m.status == MilestoneStatus.paused,
      );

  /// Ends the goal without the reward. History is kept.
  Future<void> cancel(String id, {String reason = 'cancelled'}) => _transition(
        id,
        (_) => {'status': MilestoneStatus.cancelled.name, 'endedReason': reason},
        allowed: (m) => m.isCurrent,
      );

  /// A parent decides the family has earned it early.
  Future<void> completeNow(String id) => _transition(
        id,
        (_) => {
          'status': MilestoneStatus.completed.name,
          'completedAt': Timestamp.fromDate(_clock()),
          'endedReason': 'completedByParent',
        },
        allowed: (m) => m.isCurrent,
      );

  /// New deadline (also reopens an expired goal). [deadlineDay] is a local day.
  Future<void> extend(String id, DateTime deadlineDay) {
    final endsAt = MilestoneRules.endOfDeadlineDay(deadlineDay);
    return _transition(
      id,
      (_) => {'endsAt': Timestamp.fromDate(endsAt)},
      allowed: (m) => m.isCurrent && endsAt.isAfter(m.startsAt) && endsAt.isAfter(_clock()),
      notAllowed: 'Pick a deadline from today on.',
    );
  }

  /// Closes [id] (kept in history as restarted) and starts a fresh copy from
  /// Start with a new window. Returns the new goal's id.
  Future<String> restart(String id, {required DateTime startDay, required DateTime deadlineDay}) async {
    _requireParent();
    final old = byId(id);
    if (old == null) throw Exception('This goal no longer exists.');
    final fresh = old.copyWith(
      startsAt: MilestoneRules.startOfDay(startDay),
      endsAt: MilestoneRules.endOfDeadlineDay(deadlineDay),
      status: MilestoneStatus.active,
      position: 0,
    );
    final problem = validate(fresh);
    if (problem != null) throw Exception(problem);
    if (old.isCurrent) await cancel(id, reason: 'restarted');
    final ref = _milestonesRef.doc();
    await ref.set({
      ...fresh.toFirestore(),
      'createdBy': _user!.id,
      'createdAt': Timestamp.fromDate(_clock()),
      'completedAt': null,
      'rewardClaimedAt': null,
      'restartedFrom': id,
    });
    return ref.id;
  }

  /// Closes the current goal (kept in history as replaced) so a new one can
  /// be created.
  Future<void> replace(String id) => cancel(id, reason: 'replaced');

  /// Marks the shared reward as enjoyed. Only once.
  Future<void> claimReward(String id) => _transition(
        id,
        (_) => {
          'rewardClaimedAt': Timestamp.fromDate(_clock()),
          'rewardClaimedBy': _user!.id,
        },
        allowed: (m) => m.isCompleted && !m.isRewardClaimed,
        notAllowed: 'This reward was already claimed.',
      );

  /// Recomputes the position from the contribution audit trail (repairs a
  /// board after manual data fixes). Never completes or reopens a goal.
  Future<int> recalculate(String id) async {
    _requireParent();
    final ref = _milestonesRef.doc(id);
    final contributions = await ref.collection('contributions').get();
    final list = contributions.docs.map(MilestoneContribution.fromFirestore);
    late int position;
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('This goal no longer exists.');
      final stored = FamilyMilestone.fromFirestore(snap);
      position = MilestoneRules.recalculate(list, stored.boardLength);
      tx.update(ref, {'position': position});
    });
    return position;
  }

  // --- Child --------------------------------------------------------------------

  /// Marks [events] as shown so they never play again (on any device).
  Future<void> markPresented(Iterable<ProgressEvent> events) async {
    final ids = events.map((e) => e.taskId).toSet();
    if (ids.isEmpty || _householdId == null) return;
    // Drop them locally right away so the presenter can't fire twice while
    // the write is in flight (or offline).
    unpresentedEvents = unpresentedEvents.where((e) => !ids.contains(e.taskId)).toList();
    notifyListeners();
    final batch = _firestore.batch();
    final at = Timestamp.fromDate(_clock());
    for (final id in ids) {
      batch.update(_householdRef.collection('progressEvents').doc(id), {'presentedAt': at});
    }
    try {
      await batch.commit();
    } catch (e) {
      debugPrint('MilestoneService: could not mark events presented: $e');
    }
  }
}
