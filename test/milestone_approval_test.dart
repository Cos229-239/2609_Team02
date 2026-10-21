import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/family_milestone.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/services/database_service.dart';

/// Task approval → family milestone contribution, board move and the
/// child's progress event, all in the approval transaction.
void main() {
  const householdId = 'h1';
  const childId = 'kid';
  const otherChildId = 'kid2';
  const parentId = 'parent';
  final now = DateTime(2026, 10, 5, 18);

  late FakeFirebaseFirestore firestore;
  late DatabaseService db;

  DocumentReference<Map<String, dynamic>> household() => firestore.collection('households').doc(householdId);
  DocumentReference<Map<String, dynamic>> milestoneRef([String id = 'm1']) =>
      household().collection('milestones').doc(id);

  Future<void> addMilestone({
    String id = 'm1',
    MilestoneStatus status = MilestoneStatus.active,
    int position = 0,
    int boardLength = 5,
    int spacesPerTask = 1,
    MilestoneEligibility eligibility = const MilestoneEligibility(),
  }) async {
    await milestoneRef(id).set({
      ...FamilyMilestone(
        id: id,
        title: 'Park day',
        rewardTitle: 'Amusement park',
        startsAt: DateTime(2026, 10, 1),
        endsAt: DateTime(2026, 10, 15),
        status: status,
        position: position,
        boardLength: boardLength,
        spacesPerTask: spacesPerTask,
        eligibility: eligibility,
      ).toFirestore(),
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
    });
  }

  Future<void> addTask(
    String id, {
    String? assignee = childId,
    TaskStatus status = TaskStatus.completed,
    String? scheduleId,
    DateTime? completedAt,
  }) async {
    await household().collection('tasks').doc(id).set({
      ...TaskModel(
        id: id,
        title: 'Task $id',
        assignedToUserId: assignee,
        rewardXp: 20,
        coinReward: 5,
        status: status,
        completedAt: status == TaskStatus.pending ? null : (completedAt ?? DateTime(2026, 10, 5, 10)),
      ).toFirestore(),
      'scheduleId': scheduleId,
    });
  }

  Future<FamilyMilestone> milestone([String id = 'm1']) async =>
      FamilyMilestone.fromFirestore(await milestoneRef(id).get());

  Future<int> xpOf(String uid) async => (await firestore.collection('users').doc(uid).get()).data()!['xp'] as int;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    db = DatabaseService(
      firestore: firestore,
      clock: () => now,
      deviceTimeZone: () async => null,
      availableMiniGames: const [],
    );
    await household().set({
      'name': 'Test',
      'ownerId': parentId,
      'memberIds': [parentId, childId, otherChildId],
    });
    for (final (uid, role) in [(parentId, 'parent'), (childId, 'child'), (otherChildId, 'child')]) {
      await firestore.collection('users').doc(uid).set({'name': uid, 'role': role, 'xp': 0, 'coins': 0});
    }
    db.bindHousehold(householdId);
  });

  test('an approved task contributes exactly once and moves the board', () async {
    await addMilestone();
    await addTask('t1');

    await db.approveTask('t1');
    await db.approveTask('t1'); // retried / double tap

    final m = await milestone();
    expect(m.position, 1);
    final contributions = await milestoneRef().collection('contributions').get();
    expect(contributions.docs.map((d) => d.id), ['t1']);
    final c = MilestoneContribution.fromFirestore(contributions.docs.single);
    expect(c.childId, childId);
    expect(c.fromPosition, 0);
    expect(c.toPosition, 1);
    expect(c.spaces, 1);
    expect(await xpOf(childId), 20, reason: 'base XP still paid once');

    final event = await household().collection('progressEvents').doc('t1').get();
    expect(event.exists, isTrue);
    expect(event.data()!['fromPosition'], 0);
    expect(event.data()!['toPosition'], 1);
    expect(event.data()!['presentedAt'], isNull);
  });

  test('approval, contribution and board move are one transaction (retry after commit is a no-op)', () async {
    await addMilestone();
    await addTask('t1');
    await db.approveTask('t1');
    // Simulate the task being reset to "completed" and approved again
    // (e.g. reassigned then re-approved): same occurrence id, no double count.
    await household().collection('tasks').doc('t1').update({'status': 'completed'});
    await db.approveTask('t1');
    expect((await milestone()).position, 1);
    expect((await milestoneRef().collection('contributions').get()).size, 1);
  });

  test('each recurring occurrence counts on its own', () async {
    await addMilestone();
    await addTask('dishes_20261004', scheduleId: 'dishes');
    await addTask('dishes_20261005', scheduleId: 'dishes');
    await db.approveTask('dishes_20261004');
    await db.approveTask('dishes_20261005');
    expect((await milestone()).position, 2);
  });

  test('pending (not completed) tasks are not approved and do not move the board', () async {
    await addMilestone();
    await addTask('t1', status: TaskStatus.pending);
    await db.approveTask('t1'); // approve only works on completed tasks
    expect((await milestone()).position, 0);
    expect((await household().collection('progressEvents').get()).size, 0);
  });

  test('a parent marking a pending task done counts (parent approval flow)', () async {
    await addMilestone();
    await addTask('t1', status: TaskStatus.pending);
    await db.parentCompleteTask('t1');
    expect((await milestone()).position, 1);
  });

  test('ineligible tasks, paused goals and tasks done outside the window do not count', () async {
    await addMilestone(eligibility: const MilestoneEligibility(oneTimeTasks: false));
    await addTask('one-time');
    await db.approveTask('one-time');
    expect((await milestone()).position, 0);

    await milestoneRef().update({'eligibility': const MilestoneEligibility().toMap(), 'status': 'paused'});
    await addTask('while-paused');
    await db.approveTask('while-paused');
    expect((await milestone()).position, 0);

    await milestoneRef().update({'status': 'active'});
    await addTask('too-early', completedAt: DateTime(2026, 9, 20));
    await db.approveTask('too-early');
    expect((await milestone()).position, 0);
    expect((await household().collection('progressEvents').get()).size, 0);
  });

  test('unassigned and parent-assigned tasks never move the board', () async {
    await addMilestone();
    await addTask('pool', assignee: null);
    await addTask('mine', assignee: parentId);
    await db.approveTask('pool');
    await db.approveTask('mine');
    expect((await milestone()).position, 0);
  });

  test('every child moves the same shared piece; reaching the end completes the goal', () async {
    await addMilestone(boardLength: 5, spacesPerTask: 3);
    await addTask('a');
    await addTask('b', assignee: otherChildId);
    await addTask('c');

    await db.approveTask('a');
    await db.approveTask('b');
    final m = await milestone();
    expect(m.position, 5, reason: 'capped at the finish');
    expect(m.status, MilestoneStatus.completed);
    expect(m.completedAt, now);

    final last = await household().collection('progressEvents').doc('b').get();
    expect(last.data()!['milestoneCompleted'], isTrue);
    expect(last.data()!['childId'], otherChildId);

    await db.approveTask('c'); // after completion: nothing moves
    expect((await milestone()).position, 5);
    expect((await milestoneRef().collection('contributions').get()).size, 2);
  });

  // Real Firestore serialises the two transactions (the loser retries and
  // re-reads the milestone); the fake runs them back to back, so this checks
  // that each parent's device builds on the stored position, not a cached one.
  test('approvals from two parents\' devices both count on the shared board', () async {
    await addMilestone(boardLength: 10);
    await addTask('a');
    await addTask('b', assignee: otherChildId);
    final second = DatabaseService(
      firestore: firestore,
      clock: () => now,
      deviceTimeZone: () async => null,
      availableMiniGames: const [],
    )
      ..bindHousehold(householdId);
    await db.approveTask('a');
    await second.approveTask('b');
    await second.approveTask('a'); // the other parent taps the same task too
    final m = await milestone();
    expect(m.position, 2);
    final positions = (await milestoneRef().collection('contributions').get())
        .docs
        .map((d) => '${d.data()['fromPosition']}->${d.data()['toPosition']}')
        .toSet();
    expect(positions, {'0->1', '1->2'});
  });

  test('approving still works when there is no family goal', () async {
    await addTask('t1');
    await db.approveTask('t1');
    expect(await xpOf(childId), 20);
    expect((await household().collection('progressEvents').get()).size, 0);
  });
}
