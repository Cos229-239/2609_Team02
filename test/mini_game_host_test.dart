import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_session.dart';
import 'package:famotive/core/models/mini_game_settings.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/mini_game_service.dart';
import 'package:famotive/features/minigames/mini_game_framework.dart';
import 'package:famotive/features/minigames/screens/mini_game_host_screen.dart';

/// A stand-in game: one button that finishes with a fixed performance.
class _FakeGame extends MiniGameDefinition {
  const _FakeGame(this.performance);

  final double performance;

  @override
  MiniGameId get id => MiniGameId.balloonPopper;

  @override
  Widget build(BuildContext context, MiniGamePlayContext play) {
    return Center(
      child: ElevatedButton(
        key: const Key('fake-finish'),
        onPressed: () {
          play.onFinished(MiniGameOutcome(
            gameId: id,
            details: {'popped': (performance * 10).round(), 'target': 10},
            performance: performance,
            elapsed: const Duration(seconds: 20),
            completed: performance == 1,
          ));
          // A second report (e.g. double tap) is ignored by the host.
          play.onFinished(MiniGameOutcome(gameId: id, details: const {}, performance: 0, elapsed: Duration.zero));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('seed ${play.seed}'),
            Text('target ${play.settings.balloonPopper.targetCount}'),
          ],
        ),
      ),
    );
  }
}

void main() {
  const householdId = 'h1';
  const child = AppUser(id: 'kid', name: 'Ava', email: 'k@x', role: UserRole.child, householdId: householdId);
  late FakeFirebaseFirestore firestore;
  late MiniGameService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = MiniGameService(firestore: firestore)..bind(child);
  });

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => ChangeNotifierProvider<MiniGameService>.value(
        value: service,
        child: MaterialApp(home: home),
      );

  testWidgets('casual play: intro → game → practice result, nothing written', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(app(const MiniGameHostScreen(
      gameId: MiniGameId.balloonPopper,
      casualSettings: MiniGameSettings(),
      casualSeed: 7,
      definition: _FakeGame(0.5),
    )));
    expect(find.textContaining('Practice round'), findsOneWidget);
    expect(find.text('Skip bonus'), findsNothing);
    await tester.tap(find.byKey(const Key('minigame-play')));
    await tester.pump();
    expect(find.text('seed 7'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fake-finish')));
    await tester.pump();
    expect(find.text('Score: 50%'), findsOneWidget);
    expect(find.textContaining('no XP this time'), findsOneWidget);
    expect(find.textContaining('1.5×'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
    expect((await firestore.collectionGroup('miniGameSessions').get()).size, 0);
  });

  testWidgets('casual play: the child picks Easy / Medium / Hard', (tester) async {
    tallScreen(tester);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(app(const MiniGameHostScreen(
      gameId: MiniGameId.balloonPopper,
      casualSettings: MiniGameSettings(),
      casualSeed: 7,
      definition: _FakeGame(0.5),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practice-difficulty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('practice-difficulty-hard')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('minigame-play')));
    await tester.pump();
    expect(find.text('target 25'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fake-finish')));
    await tester.pump();
    // Switch to Easy on the result screen; Play again uses it.
    await tester.tap(find.byKey(const Key('practice-difficulty-easy')));
    await tester.pump();
    await tester.tap(find.text('Play again'));
    await tester.pump();
    expect(find.text('target 10'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('minigames.practiceDifficulty'), 'easy');
  });

  testWidgets('rewarded play: no difficulty picker', (tester) async {
    tallScreen(tester);
    final ref = firestore.collection('households').doc(householdId).collection('miniGameSessions').doc('t0');
    await ref.set(MiniGameSession.offer(
      childId: 'kid',
      taskId: 't0',
      taskTitle: 'Dishes',
      gameId: MiniGameId.balloonPopper,
      seed: 1,
      baseXp: 20,
      settings: const MiniGameSettings(),
      now: DateTime.now(),
    ));
    final session = MiniGameSession.fromFirestore(await ref.get());
    await tester.pumpWidget(app(MiniGameHostScreen.rewarded(session: session, definition: const _FakeGame(0.5))));
    expect(find.byKey(const Key('practice-difficulty')), findsNothing);
  });

  testWidgets('rewarded play: start and finish are recorded; the bonus is shown once confirmed', (tester) async {
    tallScreen(tester);
    final ref = firestore.collection('households').doc(householdId).collection('miniGameSessions').doc('t1');
    await ref.set(MiniGameSession.offer(
      childId: 'kid',
      taskId: 't1',
      taskTitle: 'Dishes',
      gameId: MiniGameId.balloonPopper,
      seed: 1000,
      baseXp: 20,
      settings: const MiniGameSettings(),
      now: DateTime.now(),
    ));
    final session = MiniGameSession.fromFirestore(await ref.get());

    await tester.pumpWidget(app(MiniGameHostScreen.rewarded(session: session, definition: const _FakeGame(0.5))));
    expect(find.textContaining('Bonus round for "Dishes"'), findsOneWidget);
    expect(find.textContaining('up to 40 XP (2×)'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('minigame-play')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('seed 1000'), findsOneWidget, reason: 'attempt 1 uses the session seed');
    expect((await ref.get()).data()!['status'], 'started');

    await tester.tap(find.byKey(const Key('fake-finish')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    final raw = (await ref.get()).data()!;
    expect(raw['status'], 'finished');
    expect(raw['outcome']['details'], {'popped': 5, 'target': 10});

    await tester.pump();
    expect(find.text('20 XP'), findsOneWidget); // task XP
    expect(find.text('1.5×'), findsOneWidget);
    expect(find.text('+10 XP'), findsOneWidget);
    expect(find.text('30 XP'), findsOneWidget);
    expect(find.textContaining('Adding your bonus'), findsOneWidget);

    // The server settles it.
    await tester.runAsync(() async {
      await ref.update({'status': 'rewarded', 'multiplierPct': 150, 'bonusXp': 10, 'finalXp': 30});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.textContaining('Bonus added'), findsOneWidget);
  });

  testWidgets('leaving mid-game asks first and keeps the session replayable', (tester) async {
    tallScreen(tester);
    final ref = firestore.collection('households').doc(householdId).collection('miniGameSessions').doc('t1');
    await ref.set(MiniGameSession.offer(
      childId: 'kid',
      taskId: 't1',
      taskTitle: 'Dishes',
      gameId: MiniGameId.balloonPopper,
      seed: 1,
      baseXp: 20,
      settings: const MiniGameSettings(),
      now: DateTime.now(),
    ));
    final session = MiniGameSession.fromFirestore(await ref.get());
    await tester.pumpWidget(app(MiniGameHostScreen.rewarded(session: session, definition: const _FakeGame(1))));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('minigame-play')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.tap(find.byKey(const Key('minigame-close')));
    await tester.pumpAndSettle();
    expect(find.text('Leave the game?'), findsOneWidget);
    expect(find.textContaining('one more time'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake-finish')), findsOneWidget);
    expect((await ref.get()).data()!['status'], 'started');
  });

  testWidgets('skipping the bonus marks the session skipped', (tester) async {
    tallScreen(tester);
    final ref = firestore.collection('households').doc(householdId).collection('miniGameSessions').doc('t1');
    await ref.set(MiniGameSession.offer(
      childId: 'kid',
      taskId: 't1',
      taskTitle: 'Dishes',
      gameId: MiniGameId.balloonPopper,
      seed: 1,
      baseXp: 20,
      settings: const MiniGameSettings(),
      now: DateTime.now(),
    ));
    final session = MiniGameSession.fromFirestore(await ref.get());
    await tester.pumpWidget(app(Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => MiniGameHostScreen.rewarded(session: session, definition: const _FakeGame(1)),
      ),
    )));
    await tester.tap(find.text('Skip bonus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect((await ref.get()).data()!['status'], 'skipped');
  });
}
