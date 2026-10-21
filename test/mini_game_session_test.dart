import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_session.dart';
import 'package:famotive/core/models/mini_game_settings.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/approval_effects.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/core/services/mini_game_service.dart';

/// Approval → one rewarded bonus session; the child's session lifecycle;
/// parent settings with child overrides.
void main() {
  const householdId = 'h1';
  const childId = 'kid';
  const parentId = 'parent';
  final now = DateTime(2026, 10, 5, 18);
  const child = AppUser(id: childId, name: 'Ava', email: 'k@x', role: UserRole.child, householdId: householdId);
  const parent = AppUser(id: parentId, name: 'Pat', email: 'p@x', role: UserRole.parent, householdId: householdId);

  late FakeFirebaseFirestore firestore;
  late DatabaseService db;

  DocumentReference<Map<String, dynamic>> household() => firestore.collection('households').doc(householdId);
  CollectionReference<Map<String, dynamic>> sessions() => household().collection('miniGameSessions');
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> addTask(String id, {int xp = 20, String? assignee = childId}) =>
      household().collection('tasks').doc(id).set(TaskModel(
            id: id,
            title: 'Task $id',
            assignedToUserId: assignee,
            rewardXp: xp,
            status: TaskStatus.completed,
            completedAt: DateTime(2026, 10, 5, 10),
          ).toFirestore());

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    db = DatabaseService(
      firestore: firestore,
      clock: () => now,
      deviceTimeZone: () async => null,
      approvalEffects: ApprovalEffects(firestore, random: math.Random(1)),
    );
    await household().set({'name': 'Test', 'ownerId': parentId, 'memberIds': [parentId, childId]});
    await firestore.collection('users').doc(childId).set({'name': 'Ava', 'role': 'child', 'xp': 0, 'coins': 0});
    await firestore.collection('users').doc(parentId).set({'name': 'Pat', 'role': 'parent', 'xp': 0, 'coins': 0});
    db.bindHousehold(householdId);
  });

  group('offering a bonus game at approval', () {
    test('one rewarded session per approved task, with settings snapshotted', () async {
      await household().collection('miniGameSettings').doc('household').set({
        'matchPairs': {'pairs': 8},
      });
      await household().collection('miniGameSettings').doc(childId).set({
        'matchPairs': {'maxMisses': 5},
        'multiplier': {'maxPct': 150},
      });
      await addTask('t1');
      await db.approveTask('t1');
      expect((await firestore.collection('users').doc(childId).get()).data()!['xp'], 20,
          reason: 'approval pays only the base XP; the bonus is server-paid later');
      await household().collection('tasks').doc('t1').update({'status': 'completed'});
      await db.approveTask('t1'); // retry: no second session

      final all = await sessions().get();
      expect(all.docs.map((d) => d.id), ['t1']);
      final s = MiniGameSession.fromFirestore(all.docs.single);
      expect(s.childId, childId);
      expect(s.status, MiniGameSessionStatus.offered);
      expect(s.baseXp, 20);
      expect(s.attempts, 0);
      expect(s.expiresAt, now.add(MiniGameSession.lifetime));
      expect(s.settings.matchPairs.pairs, 8);
      expect(s.settings.matchPairs.maxMisses, 5);
      expect(s.settings.multiplier.maxPct, 150);

      final event = await household().collection('progressEvents').doc('t1').get();
      expect(event.data()!['miniGameSessionId'], 't1');
    });

    test('random selection is reproducible with a seeded source', () async {
      Future<List<String>> run() async {
        final fs = FakeFirebaseFirestore();
        await fs.collection('households').doc(householdId).set({'memberIds': [childId]});
        await fs.collection('users').doc(childId).set({'role': 'child', 'xp': 0, 'coins': 0});
        final service = DatabaseService(
          firestore: fs,
          clock: () => now,
          deviceTimeZone: () async => null,
          approvalEffects: ApprovalEffects(fs, random: math.Random(99)),
        )..bindHousehold(householdId);
        final games = <String>[];
        for (var i = 0; i < 6; i++) {
          await fs.collection('households').doc(householdId).collection('tasks').doc('t$i').set(
                TaskModel(id: 't$i', title: 't', assignedToUserId: childId, status: TaskStatus.completed).toFirestore(),
              );
          await service.approveTask('t$i');
          final s = await fs.collection('households').doc(householdId).collection('miniGameSessions').doc('t$i').get();
          games.add('${s.data()!['gameId']}/${s.data()!['seed']}');
        }
        return games;
      }

      expect(await run(), await run());
    });

    test('no session when parents switched bonus games off, for 0-XP tasks, or for non-children', () async {
      await household().collection('miniGameSettings').doc(childId).set({'rewardedGamesEnabled': false});
      await addTask('off');
      await db.approveTask('off');
      await household().collection('miniGameSettings').doc(childId).delete();
      await addTask('zero', xp: 0);
      await db.approveTask('zero');
      await addTask('parents', assignee: parentId);
      await db.approveTask('parents');
      expect((await sessions().get()).size, 0);
    });

    test('games this build does not include are never offered', () async {
      final limited = DatabaseService(
        firestore: firestore,
        clock: () => now,
        deviceTimeZone: () async => null,
        approvalEffects: ApprovalEffects(firestore, availableGames: const [MiniGameId.memoryRun]),
      )..bindHousehold(householdId);
      await addTask('t1');
      await limited.approveTask('t1');
      expect((await sessions().doc('t1').get()).data()!['gameId'], 'memoryRun');
    });
  });

  group('MiniGameService', () {
    late MiniGameService kid;

    Future<MiniGameSession> offered() async {
      await addTask('t1');
      await db.approveTask('t1');
      await settle();
      return MiniGameSession.fromFirestore(await sessions().doc('t1').get());
    }

    setUp(() async {
      kid = MiniGameService(firestore: firestore, clock: () => now)..bind(child);
      await settle();
    });

    test('lists the open bonus games of the signed-in child only', () async {
      final s = await offered();
      await settle();
      expect(kid.openSessions.map((e) => e.id), [s.id]);
      final parentView = MiniGameService(firestore: firestore, clock: () => now)..bind(parent);
      await settle();
      expect(parentView.openSessions, isEmpty);
    });

    test('start → finish records attempts, server timestamps and the outcome', () async {
      final s = await offered();
      expect(await kid.start(s), 1);
      var stored = MiniGameSession.fromFirestore(await sessions().doc('t1').get());
      expect(stored.status, MiniGameSessionStatus.started);
      expect(stored.attempts, 1);
      expect(stored.startedAt, isNotNull);

      await kid.finish(
        stored,
        const MiniGameOutcome(
          gameId: MiniGameId.balloonPopper,
          details: {'popped': 10, 'target': 15},
          performance: 10 / 15,
          elapsed: Duration(seconds: 30),
        ),
      );
      final raw = (await sessions().doc('t1').get()).data()!;
      expect(raw['status'], 'finished');
      expect(raw['outcome']['details'], {'popped': 10, 'target': 15});
      expect(raw['finishedAt'], isNotNull);
      expect(raw.containsKey('bonusXp'), isFalse, reason: 'only the server writes rewards');
      stored = MiniGameSession.fromFirestore(await sessions().doc('t1').get());
      expect(stored.isAwaitingReward, isTrue);
      await expectLater(kid.start(stored), throwsException, reason: 'a finished game cannot be replayed for XP');
    });

    test('an interrupted game can be restarted once, then not again', () async {
      final s = await offered();
      await kid.start(s);
      var stored = MiniGameSession.fromFirestore(await sessions().doc('t1').get());
      expect(stored.canPlayAt(now), isTrue);
      expect(await kid.start(stored), 2);
      expect(stored.seedForAttempt(2), isNot(stored.seedForAttempt(1)));
      stored = MiniGameSession.fromFirestore(await sessions().doc('t1').get());
      expect(stored.canPlayAt(now), isFalse);
      await expectLater(kid.start(stored), throwsException);
    });

    test('expired and skipped sessions cannot be played', () async {
      final s = await offered();
      await kid.skip(s);
      final skipped = MiniGameSession.fromFirestore(await sessions().doc('t1').get());
      expect(skipped.status, MiniGameSessionStatus.skipped);
      await expectLater(kid.start(skipped), throwsException);

      final late = MiniGameService(firestore: firestore, clock: () => now.add(const Duration(days: 4)))..bind(child);
      await addTask('t2');
      await db.approveTask('t2');
      final fresh = MiniGameSession.fromFirestore(await sessions().doc('t2').get());
      expect(fresh.canPlayAt(now.add(const Duration(days: 4))), isFalse);
      await expectLater(late.start(fresh), throwsException);
    });

    test('a child cannot play a sibling\'s session', () async {
      final s = await offered();
      final sibling = MiniGameService(firestore: firestore, clock: () => now)
        ..bind(const AppUser(id: 'kid2', name: 'Bo', email: 'b@x', role: UserRole.child, householdId: householdId));
      await expectLater(sibling.start(s), throwsException);
      expect(() => sibling.skip(s), throwsException);
    });

    test('parents save household defaults and child overrides; children cannot', () async {
      final parentService = MiniGameService(firestore: firestore, clock: () => now)..bind(parent);
      await settle();
      final defaults = parentService.householdSettings;
      await parentService.saveHouseholdSettings(
        defaults.copyWith(matchPairs: MatchPairsSettings.preset(DifficultyPreset.easy)),
      );
      await parentService.saveChildOverride(childId, defaults.copyWith(rewardedGamesEnabled: false));
      await settle();
      expect(parentService.householdSettings.matchPairs.pairs, 4);
      expect(parentService.hasOverride(childId), isTrue);
      expect(parentService.settingsFor(childId).rewardedGamesEnabled, isFalse);
      expect(parentService.settingsFor('kid2').rewardedGamesEnabled, isTrue);

      await parentService.saveChildOverride(childId, null);
      await settle();
      expect(parentService.hasOverride(childId), isFalse);
      expect(parentService.settingsFor(childId).matchPairs.pairs, 4, reason: 'back to the household defaults');

      await expectLater(kid.saveHouseholdSettings(defaults), throwsException);
      await expectLater(kid.saveChildOverride(childId, defaults), throwsException);
    });
  });
}

