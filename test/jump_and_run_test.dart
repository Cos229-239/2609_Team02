import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_settings.dart';
import 'package:famotive/features/minigames/games/jump_and_run/jump_run_game.dart';
import 'package:famotive/features/minigames/games/jump_and_run/jump_run_logic.dart';
import 'package:famotive/features/minigames/mini_game_framework.dart';

/// Runs [sim] to the end. With [autopilot] it jumps when the next obstacle
/// is 3.5 m ahead (inside the ~1.2–6 m window that clears it).
void run(JumpRunSim sim, {bool autopilot = true}) {
  var guard = 0;
  while (!sim.isOver && guard++ < 100000) {
    if (autopilot) {
      for (final o in sim.course.obstacles) {
        final d = o.x - sim.x;
        if (d > 0 && d <= 3.5) {
          sim.jump();
          break;
        }
      }
    }
    sim.step(1 / 120);
  }
}

void main() {
  group('JumpRunCourse.generate', () {
    test('every generated course is completable (all densities, many seeds)', () {
      for (final density in [1, 2, 3]) {
        for (final duration in [15, 30, 90]) {
          for (var seed = 0; seed < 60; seed++) {
            final settings = JumpAndRunSettings(durationSec: duration, obstacleDensity: density);
            final course = JumpRunCourse.generate(settings, math.Random(seed));
            expect(course.isCompletable, isTrue, reason: 'density $density, $duration s, seed $seed');
          }
        }
      }
    });

    test('a well-timed runner finishes every course without a single hit', () {
      for (final density in [1, 2, 3]) {
        for (var seed = 0; seed < 25; seed++) {
          final sim = JumpRunSim(JumpRunCourse.generate(JumpAndRunSettings(obstacleDensity: density), math.Random(seed)));
          run(sim);
          expect(sim.isFinished, isTrue, reason: 'density $density seed $seed');
          expect(sim.hits, 0, reason: 'density $density seed $seed');
          expect(sim.obstaclesCleared, sim.course.obstacles.length);
        }
      }
    });

    test('layouts are seeded; density and star frequency follow the settings', () {
      String layout(int seed) => JumpRunCourse.generate(const JumpAndRunSettings(), math.Random(seed))
          .obstacles
          .map((o) => o.x.toStringAsFixed(2))
          .join(',');
      expect(layout(3), layout(3));
      expect(layout(3), isNot(layout(4)));

      int obstacles(int density) =>
          JumpRunCourse.generate(JumpAndRunSettings(durationSec: 60, obstacleDensity: density), math.Random(1)).obstacles.length;
      expect(obstacles(3), greaterThan(obstacles(1)));

      for (final freq in [1, 2, 3]) {
        final settings = JumpAndRunSettings(collectibleFrequency: freq);
        final course = JumpRunCourse.generate(settings, math.Random(8));
        expect(course.collectibles.length, settings.collectibleCount, reason: 'the server checks this exact count');
        expect(course.runLength, settings.runLength);
      }
    });
  });

  group('JumpRunSim', () {
    test('never jumping: obstacles cost hearts and the run fails after three', () {
      final course = JumpRunCourse.generate(const JumpAndRunSettings(obstacleDensity: 3), math.Random(2));
      expect(course.obstacles.length, greaterThanOrEqualTo(3));
      final sim = JumpRunSim(course);
      run(sim, autopilot: false);
      expect(sim.isFailed, isTrue);
      expect(sim.hits, 3);
      expect(sim.hearts, 0);
      final o = sim.outcome(const Duration(seconds: 20));
      expect(o.completed, isFalse);
      expect(o.details['distance'], lessThan(course.runLength.toInt()));
      expect(o.details['hits'], 3);
      expect(o.performance, lessThan(0.7));
    });

    test('one obstacle hit only costs one heart (brief invulnerability)', () {
      final course = JumpRunCourse.generate(const JumpAndRunSettings(obstacleDensity: 1), math.Random(1));
      final sim = JumpRunSim(course);
      final first = course.obstacles.first;
      while (sim.x < first.x + first.width + 1) {
        sim.step(1 / 120);
      }
      expect(sim.hits, 1);
      expect(sim.hearts, 2);
    });

    test('jumps only from the ground; an early tap is buffered', () {
      final sim = JumpRunSim(JumpRunCourse.generate(const JumpAndRunSettings(), math.Random(1)));
      sim.jump();
      expect(sim.vy, JumpPhysics.jumpVelocity);
      sim.step(0.05);
      final vy = sim.vy;
      sim.jump(); // mid-air: no double jump
      expect(sim.vy, vy);
      // Fall until just before landing, tap, and the next jump starts on landing.
      while (sim.vy > 0 || sim.y > 0.3) {
        sim.step(1 / 120);
      }
      sim.jump();
      for (var i = 0; i < 30 && sim.vy <= 0; i++) {
        sim.step(1 / 120);
      }
      expect(sim.vy, greaterThan(0));
    });

    test('a finished run reports the full distance and stars collected', () {
      final settings = const JumpAndRunSettings(durationSec: 15);
      final sim = JumpRunSim(JumpRunCourse.generate(settings, math.Random(5)));
      run(sim);
      final o = sim.outcome(const Duration(seconds: 15));
      expect(o.completed, isTrue);
      expect(o.details['distance'], settings.runLength);
      expect(o.details['runLength'], settings.runLength);
      expect(o.details['collectibles'], settings.collectibleCount);
      expect(o.details['collected'], inInclusiveRange(0, settings.collectibleCount));
      expect(o.performance, greaterThanOrEqualTo(0.7));
      expect(JumpPhysics.apex, greaterThan(2.0), reason: 'air stars are reachable');
    });
  });

  testWidgets('tap to jump; the run ends and reports exactly once', (tester) async {
    final reports = <MiniGameOutcome>[];
    final play = MiniGamePlayContext(
      settings: const MiniGameSettings(jumpAndRun: JumpAndRunSettings(durationSec: 15, obstacleDensity: 3)),
      seed: 2,
      onFinished: reports.add,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => const JumpAndRunMiniGame().build(c, play)))));
    expect(find.text('3'), findsOneWidget, reason: 'countdown');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('jump-area')));
    for (var i = 0; i < 400 && reports.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(reports, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(reports, hasLength(1));
    expect(reports.single.details['runLength'], 150);
  });

  test('Jump and Run is registered with the framework', () {
    expect(MiniGameRegistry.of(MiniGameId.jumpAndRun), isA<JumpAndRunMiniGame>());
  });
}
