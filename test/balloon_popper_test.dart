import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_settings.dart';
import 'package:famotive/features/minigames/games/balloon_popper/balloon_popper_game.dart';
import 'package:famotive/features/minigames/games/balloon_popper/balloon_popper_logic.dart';
import 'package:famotive/features/minigames/mini_game_framework.dart';

void main() {
  const settings = BalloonPopperSettings(targetCount: 10, timeLimitSec: 30);

  group('BalloonPopperRound.generate', () {
    test('is reproducible for a seed and varies between seeds', () {
      List<String> layout(int seed) => BalloonPopperRound.generate(settings, math.Random(seed))
          .balloons
          .map((b) => '${b.x.toStringAsFixed(3)}/${b.colorIndex}/${b.appearAtMs}/${b.riseMs}')
          .toList();
      expect(layout(1), layout(1));
      expect(layout(1), isNot(layout(2)));
    });

    test('releases spare balloons inside the time limit, spread out and on screen', () {
      for (var seed = 0; seed < 50; seed++) {
        final round = BalloonPopperRound.generate(settings, math.Random(seed));
        expect(round.balloons.length, 14, reason: '40% spare balloons');
        for (final b in round.balloons) {
          expect(b.x, inInclusiveRange(0.1, 0.9));
          expect(b.appearAtMs, inInclusiveRange(0, 24000));
          expect(b.riseMs, inInclusiveRange(4500, 7000));
          expect(b.colorIndex, inInclusiveRange(0, BalloonPopperRound.colorCount - 1));
        }
        final times = round.balloons.map((b) => b.appearAtMs).toList();
        expect(times, orderedEquals([...times]..sort()), reason: 'appear one after another');
      }
    });

    test('difficulty settings shape the round', () {
      final hard = BalloonPopperRound.generate(BalloonPopperSettings.preset(DifficultyPreset.hard), math.Random(1));
      final easy = BalloonPopperRound.generate(BalloonPopperSettings.preset(DifficultyPreset.easy), math.Random(1));
      expect(hard.target, greaterThan(easy.target));
      expect(easy.timeLimitMs, greaterThan(hard.timeLimitMs));
    });
  });

  group('BalloonPopperRound rules', () {
    late BalloonPopperRound round;
    setUp(() => round = BalloonPopperRound.generate(settings, math.Random(3)));

    int visibleTime(BalloonSpec b) => b.appearAtMs + b.riseMs ~/ 2;

    test('a balloon counts once, only while it is visible', () {
      final b = round.balloons.first;
      expect(round.pop(b.id, b.appearAtMs - 1), isFalse, reason: 'not released yet');
      expect(round.pop(b.id, visibleTime(b)), isTrue);
      expect(round.pop(b.id, visibleTime(b) + 10), isFalse, reason: 'double tap');
      expect(round.popped, 1);
      final gone = round.balloons[1];
      expect(round.pop(gone.id, gone.appearAtMs + gone.riseMs), isFalse, reason: 'floated away');
      expect(round.pop(999, 1000), isFalse);
    });

    test('ends when the target is reached or time runs out', () {
      expect(round.isOverAt(0), isFalse);
      expect(round.isOverAt(settings.timeLimitSec * 1000), isTrue);
      for (final b in round.balloons.take(10)) {
        round.pop(b.id, visibleTime(b));
      }
      expect(round.reachedTarget, isTrue);
      expect(round.isOverAt(1), isTrue);
      final extra = round.balloons[11];
      expect(round.pop(extra.id, visibleTime(extra)), isFalse, reason: 'no popping after the end');
    });

    test('outcome reports the counts the server checks', () {
      for (final b in round.balloons.take(4)) {
        round.pop(b.id, visibleTime(b));
      }
      round.miss();
      final o = round.outcome(30000);
      expect(o.gameId, MiniGameId.balloonPopper);
      expect(o.details, {'popped': 4, 'target': 10});
      expect(o.performance, 0.4);
      expect(o.completed, isFalse);
      expect(o.elapsed, const Duration(seconds: 30));
    });
  });

  testWidgets('tapping a balloon pops it; the game reports once when time is up', (tester) async {
    MiniGameOutcome? result;
    var reports = 0;
    final play = MiniGamePlayContext(
      settings: const MiniGameSettings(balloonPopper: BalloonPopperSettings(targetCount: 5, timeLimitSec: 15)),
      seed: 11,
      onFinished: (o) {
        result = o;
        reports++;
      },
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => const BalloonPopperGame().build(c, play)))));
    expect(find.text('🎈 0 / 5'), findsOneWidget);

    // Let the first balloon rise into view, then tap it.
    final round = BalloonPopperRound.generate(play.settings.balloonPopper, math.Random(11));
    final first = round.balloons.first;
    await tester.pump(Duration(milliseconds: first.appearAtMs + first.riseMs ~/ 3));
    final balloon = find.byKey(ValueKey('balloon-${first.id}'));
    expect(balloon, findsOneWidget);
    await tester.tapAt(tester.getTopLeft(balloon) + const Offset(36, 36));
    await tester.pump();
    expect(find.text('🎈 1 / 5'), findsOneWidget);
    expect(find.byKey(ValueKey('balloon-${first.id}')), findsNothing);

    await tester.pump(const Duration(seconds: 16));
    expect(reports, 1);
    expect(result!.details['popped'], 1);
    expect(result!.details['target'], 5);
  });

  test('Balloon Popper is registered with the framework', () {
    expect(MiniGameRegistry.of(MiniGameId.balloonPopper), isA<BalloonPopperGame>());
  });
}
