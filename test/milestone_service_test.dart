import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/family_milestone.dart';
import 'package:famotive/core/models/progress_event.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/milestone_service.dart';

void main() {
  const householdId = 'h1';
  final now = DateTime(2026, 10, 5, 12);
  const parent = AppUser(id: 'p', name: 'Pat', email: 'p@x', role: UserRole.parent, householdId: householdId);
  const child = AppUser(id: 'kid', name: 'Ava', email: 'k@x', role: UserRole.child, householdId: householdId);

  late FakeFirebaseFirestore firestore;
  late MilestoneService service;

  FamilyMilestone draft({int boardLength = 10, String title = 'Park day'}) => FamilyMilestone(
        id: '',
        title: title,
        rewardTitle: 'Amusement park',
        startsAt: DateTime(2026, 10, 1),
        endsAt: DateTime(2026, 10, 15),
        boardLength: boardLength,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  CollectionReference<Map<String, dynamic>> milestones() =>
      firestore.collection('households').doc(householdId).collection('milestones');

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = MilestoneService(firestore: firestore, clock: () => now)..bind(parent);
    await settle();
  });

  test('validate catches empty names, rewards, inverted dates and bad board sizes', () {
    expect(MilestoneService.validate(draft()), isNull);
    expect(MilestoneService.validate(draft(title: '  ')), isNotNull);
    expect(MilestoneService.validate(draft().copyWith(rewardTitle: '')), isNotNull);
    expect(MilestoneService.validate(draft().copyWith(endsAt: DateTime(2026, 10, 1))), isNotNull);
    expect(MilestoneService.validate(draft(boardLength: 4)), isNotNull);
    expect(MilestoneService.validate(draft(boardLength: 61)), isNotNull);
    expect(
      MilestoneService.validate(draft().copyWith(
        eligibility: const MilestoneEligibility(oneTimeTasks: false, repeating: RepeatingEligibility.none),
      )),
      isNotNull,
    );
  });

  test('a parent creates one current goal at a time', () async {
    final id = await service.create(draft());
    await settle();
    expect(service.current?.id, id);
    expect(service.current?.position, 0);
    expect(service.current?.createdBy, 'p');
    expect(() => service.create(draft(title: 'Second')), throwsException);
  });

  test('children cannot create or manage goals', () async {
    final kidService = MilestoneService(firestore: firestore, clock: () => now)..bind(child);
    expect(() => kidService.create(draft()), throwsException);
    final id = await service.create(draft());
    expect(() => kidService.pause(id), throwsException);
  });

  test('editing keeps progress and refuses a board shorter than the position', () async {
    final id = await service.create(draft());
    await milestones().doc(id).update({'position': 7});
    await settle();
    final stored = service.byId(id)!;
    await service.update(stored.copyWith(title: 'Bigger park day', boardLength: 12, position: 0));
    final after = FamilyMilestone.fromFirestore(await milestones().doc(id).get());
    expect(after.title, 'Bigger park day');
    expect(after.boardLength, 12);
    expect(after.position, 7, reason: 'edits never touch progress');
    await expectLater(service.update(after.copyWith(boardLength: 6)), throwsException);
  });

  test('pause, resume, cancel, complete and extend', () async {
    final id = await service.create(draft());
    await service.pause(id);
    expect((await milestones().doc(id).get()).data()!['status'], 'paused');
    await expectLater(service.pause(id), throwsException);
    await service.resume(id);
    await service.extend(id, DateTime(2026, 10, 31));
    expect(
      FamilyMilestone.fromFirestore(await milestones().doc(id).get()).endsAt,
      DateTime(2026, 11, 1),
    );
    await expectLater(service.extend(id, DateTime(2026, 9, 1)), throwsException);
    await service.completeNow(id);
    final done = FamilyMilestone.fromFirestore(await milestones().doc(id).get());
    expect(done.status, MilestoneStatus.completed);
    expect(done.completedAt, now);
    await expectLater(service.cancel(id), throwsException, reason: 'completed goals stay completed');
  });

  test('the shared reward can be claimed only once, and only after completion', () async {
    final id = await service.create(draft());
    await expectLater(service.claimReward(id), throwsException);
    await service.completeNow(id);
    await service.claimReward(id);
    await expectLater(service.claimReward(id), throwsException);
    final m = FamilyMilestone.fromFirestore(await milestones().doc(id).get());
    expect(m.rewardClaimedAt, now);
    expect(m.rewardClaimedBy, 'p');
  });

  test('restart keeps the old goal in history and starts a fresh board', () async {
    final id = await service.create(draft());
    await milestones().doc(id).update({'position': 4});
    await settle();
    final newId = await service.restart(id, startDay: DateTime(2026, 10, 5), deadlineDay: DateTime(2026, 10, 20));
    await settle();
    final old = service.byId(id)!;
    expect(old.status, MilestoneStatus.cancelled);
    expect(old.endedReason, 'restarted');
    expect(service.current!.id, newId);
    expect(service.current!.position, 0);
    expect(service.current!.startsAt, DateTime(2026, 10, 5));
    expect(service.history.map((m) => m.id), [id]);
  });

  test('recalculate rebuilds the position from contributions', () async {
    final id = await service.create(draft());
    final contributions = milestones().doc(id).collection('contributions');
    for (final (task, spaces) in [('a', 2), ('b', 1), ('c', 3)]) {
      await contributions.doc(task).set(MilestoneContribution(
            taskId: task,
            childId: 'kid',
            spaces: spaces,
            fromPosition: 0,
            toPosition: spaces,
            approvedAt: now,
          ).toFirestore());
    }
    await milestones().doc(id).update({'position': 99});
    expect(await service.recalculate(id), 6);
    expect((await milestones().doc(id).get()).data()!['position'], 6);
  });

  test('a child sees each unpresented event once', () async {
    final events = firestore.collection('households').doc(householdId).collection('progressEvents');
    ProgressEvent event(String id, String childId, int minute) => ProgressEvent(
          taskId: id,
          childId: childId,
          createdAt: DateTime(2026, 10, 5, 12, minute),
          milestoneId: 'm1',
          fromPosition: 0,
          toPosition: 1,
          boardLength: 10,
        );
    await events.doc('b').set(event('b', 'kid', 2).toFirestore());
    await events.doc('a').set(event('a', 'kid', 1).toFirestore());
    await events.doc('other').set(event('other', 'someone-else', 1).toFirestore());

    final kid = MilestoneService(firestore: firestore, clock: () => now)..bind(child);
    await settle();
    expect(kid.unpresentedEvents.map((e) => e.taskId), ['a', 'b']);

    await kid.markPresented(kid.unpresentedEvents);
    expect(kid.unpresentedEvents, isEmpty);
    await settle();
    expect(kid.unpresentedEvents, isEmpty);
    expect((await events.doc('a').get()).data()!['presentedAt'], isNotNull);

    // A second device / app restart doesn't replay them.
    final restarted = MilestoneService(firestore: firestore, clock: () => now)..bind(child);
    await settle();
    expect(restarted.unpresentedEvents, isEmpty);
  });

  test('switching households clears everything from the previous one', () async {
    await service.create(draft());
    await settle();
    expect(service.milestones, isNotEmpty);
    service.bind(parent.copyWith(householdId: 'other'));
    expect(service.milestones, isEmpty);
    expect(service.householdId, 'other');
  });
}
