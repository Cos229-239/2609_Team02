import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/family_milestone.dart';
import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_session.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/approval_effects.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/core/services/milestone_service.dart';
import 'package:famotive/core/services/mini_game_service.dart';
import 'package:famotive/core/services/xp_multiplier.dart';

/// The whole family-goal journey across a parent's and a child's devices.
/// (The server-side bonus payment is covered by
/// functions/src/emulator/award.emulator.ts.)
void main() {
  const householdId = 'h1';
  const parent = AppUser(id: 'p', name: 'Pat', email: 'p@x', role: UserRole.parent, householdId: householdId);
  const child = AppUser(id: 'kid', name: 'Ava', email: 'k@x', role: UserRole.child, householdId: householdId);
  final now = DateTime(2026, 10, 5, 18);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('create goal → complete → approve → board moves once → bonus game → goal reached → reward claimed', () async {
    final firestore = FakeFirebaseFirestore();
    final household = firestore.collection('households').doc(householdId);
    await household.set({'name': 'Test', 'ownerId': 'p', 'memberIds': ['p', 'kid']});
    await firestore.collection('users').doc('p').set({...parent.toFirestore(), 'xp': 0});
    await firestore.collection('users').doc('kid').set({...child.toFirestore(), 'xp': 0});

    // Devices.
    final parentDb = DatabaseService(
      firestore: firestore,
      clock: () => now,
      deviceTimeZone: () async => null,
      approvalEffects: ApprovalEffects(firestore, random: math.Random(3)),
    )..bindHousehold(householdId);
    // Same fixed clock as the parent: the goal runs Oct 1-15, so a real
    // "now" after that made this test fail once the date passed.
    final childDb = DatabaseService(firestore: firestore, clock: () => now, deviceTimeZone: () async => null)
      ..bindHousehold(householdId);
    final parentGoals = MilestoneService(firestore: firestore, clock: () => now)..bind(parent);
    final childGoals = MilestoneService(firestore: firestore, clock: () => now)..bind(child);
    final childGames = MiniGameService(firestore: firestore, clock: () => now)..bind(child);

    // 1. Parent creates the goal with a shared reward.
    final goalId = await parentGoals.create(FamilyMilestone(
      id: '',
      title: 'Park day',
      rewardTitle: 'Amusement park',
      rewardIcon: '🎢',
      startsAt: DateTime(2026, 10, 1),
      endsAt: DateTime(2026, 10, 15),
      boardLength: 5,
      spacesPerTask: 3,
    ));
    await settle();
    expect(childGoals.featured?.id, goalId);

    // 2. Child completes a task; parent approves (twice, as a retry).
    await household.collection('tasks').doc('dishes').set(
          const TaskModel(id: 'dishes', title: 'Dishes', assignedToUserId: 'kid', rewardXp: 20).toFirestore(),
        );
    await childDb.completeTask('dishes');
    await parentDb.approveTask('dishes');
    await parentDb.approveTask('dishes');
    await settle();

    // 3. Exactly one contribution; the shared board moved and persisted.
    expect((await household.collection('milestones').doc(goalId).collection('contributions').get()).size, 1);
    expect(parentGoals.byId(goalId)!.position, 3);
    expect(childGoals.byId(goalId)!.position, 3, reason: 'the child device sees the same position');

    // 4. The child is shown the move once.
    expect(childGoals.unpresentedEvents.map((e) => e.taskId), ['dishes']);
    final event = childGoals.unpresentedEvents.single;
    expect((event.fromPosition, event.toPosition), (0, 3));
    await childGoals.markPresented([event]);
    final restartedChild = MilestoneService(firestore: firestore, clock: () => now)..bind(child);
    await settle();
    expect(restartedChild.unpresentedEvents, isEmpty, reason: 'restart / second device: not shown again');

    // 5. A bonus game was selected; the child plays it.
    await settle();
    final session = childGames.openSessions.single;
    expect(session.id, 'dishes');
    expect(MiniGameId.values, contains(session.gameId));
    final attempt = await childGames.start(session);
    expect(attempt, 1);
    final started = MiniGameSession.fromFirestore(await household.collection('miniGameSessions').doc('dishes').get());
    await childGames.finish(
      started,
      const MiniGameOutcome(
        gameId: MiniGameId.balloonPopper,
        details: {'popped': 15, 'target': 15},
        performance: 1,
        elapsed: Duration(seconds: 25),
        completed: true,
      ),
    );
    final finished = MiniGameSession.fromFirestore(await household.collection('miniGameSessions').doc('dishes').get());
    expect(finished.status, MiniGameSessionStatus.finished);
    // What the result screen previews (the server pays exactly this).
    final preview = XpMultiplier.award(baseXp: finished.baseXp, performance: 1, settings: finished.settings.multiplier);
    expect((preview.baseXp, preview.multiplierLabel, preview.bonusXp, preview.finalXp), (20, '2×', 20, 40));
    expect((await firestore.collection('users').doc('kid').get()).data()!['xp'], 20,
        reason: 'the app never pays the bonus itself');
    await expectLater(childGames.start(finished), throwsException, reason: 'cannot replay for a second bonus');

    // 6. A second approved task reaches the finish: the shared reward unlocks.
    await household.collection('tasks').doc('laundry').set(
          const TaskModel(id: 'laundry', title: 'Laundry', assignedToUserId: 'kid', rewardXp: 10).toFirestore(),
        );
    await childDb.completeTask('laundry');
    await parentDb.approveTask('laundry');
    await settle();
    final done = parentGoals.byId(goalId)!;
    expect(done.position, 5);
    expect(done.status, MilestoneStatus.completed);
    expect(childGoals.unpresentedEvents.single.milestoneCompleted, isTrue);

    // 7. The parent marks the reward enjoyed - once.
    await parentGoals.claimReward(goalId);
    await expectLater(parentGoals.claimReward(goalId), throwsException);
    await settle();
    expect(parentGoals.byId(goalId)!.isRewardClaimed, isTrue);
    expect(parentGoals.current, isNull);
    expect(parentGoals.history.single.id, goalId, reason: 'kept for later viewing');

    // 8. A child can't manage the goal.
    await expectLater(childGoals.cancel(goalId), throwsException);
  });
}
