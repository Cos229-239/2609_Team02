import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_settings.dart';
import 'package:famotive/features/minigames/games/memory_run/memory_run_game.dart';
import 'package:famotive/features/minigames/games/memory_run/memory_run_logic.dart';
import 'package:famotive/features/minigames/mini_game_framework.dart';

void main() {
  MemoryRunGame game(int target, [int seed = 1]) =>
      MemoryRunGame.generate(MemoryRunSettings(targetLength: target), math.Random(seed));

  /// Repeats the current round correctly.
  MemoryInput repeatRound(MemoryRunGame g) {
    g.demoFinished();
    var last = MemoryInput.ignored;
    for (final pad in g.currentPattern) {
      last = g.press(pad);
    }
    return last;
  }

  group('MemoryRunGame.generate', () {
    test('random, seeded sequences of exactly the target length', () {
      final g = game(8, 3);
      expect(g.sequence, hasLength(8));
      expect(g.sequence.every((p) => p >= 0 && p < MemoryRunGame.padCount), isTrue);
      expect(game(8, 3).sequence, g.sequence);
      expect(game(25, 3).sequence, isNot(game(25, 4).sequence));
    });

    test('the target is validated before a session begins: at most 25 steps', () {
      expect(game(25).sequence, hasLength(25));
      expect(
        () => MemoryRunGame.generate(const MemoryRunSettings(targetLength: 26), math.Random(1)),
        throwsArgumentError,
      );
      expect(
        () => MemoryRunGame.generate(const MemoryRunSettings(targetLength: 0), math.Random(1)),
        throwsArgumentError,
      );
      // Stored settings are capped at 25 before they ever get here.
      expect(MemoryRunSettings.fromMap({'targetLength': 400}).targetLength, 25);
    });
  });

  group('MemoryRunGame rules', () {
    test('input is ignored while the pattern is shown', () {
      final g = game(5);
      expect(g.phase, MemoryPhase.demo);
      expect(g.press(g.sequence.first), MemoryInput.ignored);
      g.demoFinished();
      expect(g.press(g.sequence.first), isNot(MemoryInput.ignored));
    });

    test('each round adds one step; a correct round waits for the next demo', () {
      final g = game(5);
      expect(g.currentPattern, hasLength(1));
      expect(repeatRound(g), MemoryInput.roundComplete);
      expect(g.phase, MemoryPhase.roundWon);
      expect(g.reached, 1);
      expect(g.press(g.sequence[0]), MemoryInput.ignored, reason: 'not your turn between rounds');
      g.nextRound();
      expect(g.round, 2);
      expect(g.currentPattern, g.sequence.sublist(0, 2));
      expect(g.phase, MemoryPhase.demo);
    });

    test('a wrong button stops the session with the rounds completed so far', () {
      final g = game(6);
      repeatRound(g);
      g.nextRound();
      repeatRound(g);
      g.nextRound();
      g.demoFinished();
      final wrong = (g.sequence[0] + 1) % MemoryRunGame.padCount;
      expect(g.press(wrong), MemoryInput.wrong);
      expect(g.phase, MemoryPhase.failed);
      expect(g.press(g.sequence[0]), MemoryInput.ignored);
      final o = g.outcome(const Duration(seconds: 20));
      expect(o.details, {'reached': 2, 'target': 6});
      expect(o.performance, closeTo(2 / 6, 1e-9));
      expect(o.completed, isFalse);
    });

    test('repeating the full 25-step sequence completes the game for the top prize', () {
      final g = game(25, 9);
      for (var r = 1; r <= 25; r++) {
        final last = repeatRound(g);
        if (r < 25) {
          expect(last, MemoryInput.roundComplete);
          g.nextRound();
        } else {
          expect(last, MemoryInput.gameComplete);
        }
      }
      expect(g.phase, MemoryPhase.completed);
      final o = g.outcome(const Duration(minutes: 5));
      expect(o.details, {'reached': 25, 'target': 25});
      expect(o.performance, 1);
      expect(o.completed, isTrue);
    });

    test('"show me again" replays the current round from the start', () {
      final g = game(5);
      repeatRound(g);
      g.nextRound();
      g.demoFinished();
      g.press(g.sequence[0]);
      g.replay();
      expect(g.phase, MemoryPhase.demo);
      expect(g.inputIndex, 0);
      g.demoFinished();
      expect(g.press(g.sequence[0]), MemoryInput.correct);
    });
  });

  testWidgets('watch, repeat, then a wrong press ends the game and reports once', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final reports = <MiniGameOutcome>[];
    final play = MiniGamePlayContext(
      settings: const MiniGameSettings(memoryRun: MemoryRunSettings(targetLength: 5, speed: 3)),
      seed: 4,
      onFinished: reports.add,
    );
    final sequence = MemoryRunGame.generate(play.settings.memoryRun, math.Random(4)).sequence;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => const MemoryRunMiniGame().build(c, play)))));
    expect(find.text('Watch closely...'), findsOneWidget);

    // Pressing during the demo does nothing.
    await tester.tap(find.byKey(ValueKey('pad-${sequence[0]}')));
    await tester.pump(const Duration(milliseconds: 700 + 450 + 50));
    expect(find.textContaining('Your turn'), findsOneWidget);
    expect(find.text('🧠 0 / 5'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('pad-${sequence[0]}')));
    await tester.pump();
    expect(find.text('Great! Next round...'), findsOneWidget);
    expect(find.text('🧠 1 / 5'), findsOneWidget);

    // Round 2 demo: 2 steps.
    await tester.pump(const Duration(milliseconds: 900 + 2 * 450 + 50));
    expect(find.textContaining('Your turn! (2 steps)'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('pad-${(sequence[0] + 1) % 4}')));
    await tester.pump();
    expect(find.textContaining('Oops'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(reports, hasLength(1));
    expect(reports.single.details, {'reached': 1, 'target': 5});
  });

  test('Memory Run is registered with the framework', () {
    expect(MiniGameRegistry.of(MiniGameId.memoryRun), isA<MemoryRunMiniGame>());
  });
}
