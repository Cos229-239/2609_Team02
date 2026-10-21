import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_settings.dart';
import 'package:famotive/core/services/xp_multiplier.dart';

void main() {
  group('XpMultiplier', () {
    // Same table as functions/src/minigames/plan.test.ts.
    const cases = <(double, MultiplierCurve, int, int, int)>[
      (0, MultiplierCurve.balanced, 100, 200, 100),
      (1, MultiplierCurve.balanced, 100, 200, 200),
      (0.5, MultiplierCurve.balanced, 100, 200, 150),
      (0.33, MultiplierCurve.balanced, 100, 200, 135),
      (0.5, MultiplierCurve.gentle, 100, 200, 160),
      (0.5, MultiplierCurve.challenging, 100, 200, 135),
      (0.8, MultiplierCurve.balanced, 120, 300, 265),
      (2, MultiplierCurve.balanced, 100, 200, 200),
      (-1, MultiplierCurve.balanced, 100, 200, 100),
    ];

    test('multiplier curve matches the shared table', () {
      for (final (p, curve, min, max, expected) in cases) {
        expect(
          XpMultiplier.multiplierPct(p, XpMultiplierSettings(minPct: min, maxPct: max, curve: curve)),
          expected,
          reason: '$p $curve $min-$max',
        );
      }
    });

    test('20 base XP at 1.5x is 30 XP: base, multiplier, bonus and final', () {
      const settings = XpMultiplierSettings();
      final award = XpMultiplier.award(baseXp: 20, performance: 0.5, settings: settings);
      expect(award.baseXp, 20);
      expect(award.multiplierPct, 150);
      expect(award.multiplierLabel, '1.5×');
      expect(award.bonusXp, 10);
      expect(award.finalXp, 30);
    });

    test('rounding is half-up integer math', () {
      expect(XpMultiplier.finalXp(15, 135), 20);
      expect(XpMultiplier.finalXp(10, 125), 13);
      expect(XpMultiplier.finalXp(0, 300), 0);
      expect(const XpAward(baseXp: 1, multiplierPct: 200, finalXp: 2).multiplierLabel, '2×');
      expect(const XpAward(baseXp: 1, multiplierPct: 125, finalXp: 1).multiplierLabel, '1.25×');
    });

    test('min and max multipliers are enforced, even when settings are out of bounds', () {
      const greedy = XpMultiplierSettings(minPct: 50, maxPct: 1000);
      expect(XpMultiplier.multiplierPct(1, greedy), XpMultiplierSettings.hardMaxPct);
      expect(XpMultiplier.multiplierPct(0, greedy), XpMultiplierSettings.hardMinPct);
      expect(XpMultiplier.multiplierPct(double.nan, const XpMultiplierSettings()), 100);
    });
  });

  group('MiniGamePerformance', () {
    test('every game maps to 0..1', () {
      expect(MiniGamePerformance.balloonPopper(popped: 15, target: 15), 1);
      expect(MiniGamePerformance.balloonPopper(popped: 20, target: 15), 1);
      expect(MiniGamePerformance.matchPairs(matched: 3, pairs: 6), 0.5);
      expect(MiniGamePerformance.memoryRun(reached: 0, target: 8), 0);
      expect(
        MiniGamePerformance.jumpAndRun(distance: 300, runLength: 300, collected: 6, collectibles: 12),
        closeTo(0.85, 1e-9),
      );
      expect(
        MiniGamePerformance.jumpAndRun(distance: 150, runLength: 300, collected: 0, collectibles: 0),
        closeTo(0.65, 1e-9),
      );
      expect(MiniGamePerformance.balloonPopper(popped: 3, target: 0), 0);
    });
  });

  group('GameSelector', () {
    test('every game can be picked and the default distribution is fair', () {
      final random = math.Random(7);
      final tally = {for (final id in MiniGameId.values) id: 0};
      for (var i = 0; i < 4000; i++) {
        final id = GameSelector.pick(const MiniGameSettings(), random);
        tally[id] = tally[id]! + 1;
      }
      for (final id in MiniGameId.values) {
        expect(tally[id], inInclusiveRange(850, 1150), reason: id.name);
      }
    });

    test('is deterministic for a seeded random source', () {
      List<MiniGameId> run() {
        final r = math.Random(123);
        return [for (var i = 0; i < 10; i++) GameSelector.pick(const MiniGameSettings(), r)];
      }

      expect(run(), run());
    });

    test('parent weights shape the distribution; weight 0 is never picked', () {
      const settings = MiniGameSettings(weights: {
        MiniGameId.balloonPopper: 0,
        MiniGameId.matchPairs: 0,
        MiniGameId.jumpAndRun: 0,
        MiniGameId.memoryRun: 3,
      });
      final r = math.Random(1);
      for (var i = 0; i < 200; i++) {
        expect(GameSelector.pick(settings, r), MiniGameId.memoryRun);
      }
    });

    test('only available games are picked', () {
      final r = math.Random(5);
      for (var i = 0; i < 100; i++) {
        expect(GameSelector.pick(const MiniGameSettings(), r, available: [MiniGameId.matchPairs]), MiniGameId.matchPairs);
      }
      expect(() => GameSelector.pick(const MiniGameSettings(), r, available: const []), throwsStateError);
    });
  });
}
