import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_settings.dart';

void main() {
  group('MiniGameSettings.resolve', () {
    test('no documents: sensible defaults (existing households need no migration)', () {
      final s = MiniGameSettings.resolve();
      expect(s.rewardedGamesEnabled, isTrue);
      for (final id in MiniGameId.values) {
        expect(s.weightOf(id), 1);
      }
      expect(s.balloonPopper.targetCount, 15);
      expect(s.matchPairs.maxMisses, 3, reason: 'three misses by default');
      expect(s.memoryRun.targetLength, 8);
      expect(s.jumpAndRun.durationSec, 30);
      expect(s.multiplier.minPct, 100);
      expect(s.multiplier.maxPct, 200);
    });

    test('household defaults apply unless the child has an explicit override', () {
      final household = {
        'balloonPopper': {'targetCount': 20, 'timeLimitSec': 45},
        'multiplier': {'maxPct': 250},
      };
      final child = {
        'balloonPopper': {'targetCount': 8},
      };
      final forSibling = MiniGameSettings.resolve(household: household);
      final forChild = MiniGameSettings.resolve(household: household, child: child);
      expect(forSibling.balloonPopper.targetCount, 20);
      expect(forChild.balloonPopper.targetCount, 8);
      expect(forChild.balloonPopper.timeLimitSec, 45, reason: 'fields the child does not override come from the household');
      expect(forChild.multiplier.maxPct, 250);
    });

    test('malformed or out-of-range values never crash and stay within safe bounds', () {
      final s = MiniGameSettings.resolve(household: {
        'rewardedGamesEnabled': 'yes',
        'weights': {'balloonPopper': 99, 'matchPairs': -4, 'jumpAndRun': 'x'},
        'balloonPopper': 'oops',
        'matchPairs': {'pairs': 1000, 'maxMisses': 0},
        'jumpAndRun': {'durationSec': double.infinity, 'obstacleDensity': 7},
        'memoryRun': {'targetLength': 400, 'speed': 2.6},
        'multiplier': {'minPct': 10, 'maxPct': 5000, 'curve': 'steep'},
      });
      expect(s.rewardedGamesEnabled, isTrue);
      expect(s.weightOf(MiniGameId.balloonPopper), 5);
      expect(s.weightOf(MiniGameId.matchPairs), 0);
      expect(s.weightOf(MiniGameId.jumpAndRun), 1);
      expect(s.balloonPopper.targetCount, 15);
      expect(s.matchPairs.pairs, 10);
      expect(s.matchPairs.maxMisses, 1);
      expect(s.jumpAndRun.durationSec, 30);
      expect(s.jumpAndRun.obstacleDensity, 3);
      expect(s.memoryRun.targetLength, MemoryRunSettings.maxSequenceLength, reason: 'capped at 25 steps');
      expect(s.memoryRun.speed, 3);
      expect(s.multiplier.minPct, 100);
      expect(s.multiplier.maxPct, 300);
      expect(s.multiplier.curve, MultiplierCurve.balanced);
    });

    test('a distribution where nothing can be picked falls back to fair', () {
      final s = MiniGameSettings.resolve(household: {
        'weights': {for (final id in MiniGameId.values) id.name: 0},
      });
      for (final id in MiniGameId.values) {
        expect(s.weightOf(id), 1);
      }
    });

    test('round-trips through toMap (what a session snapshots)', () {
      const original = MiniGameSettings(
        rewardedGamesEnabled: false,
        weights: {MiniGameId.memoryRun: 3},
        matchPairs: MatchPairsSettings(pairs: 8, maxMisses: 5),
        memoryRun: MemoryRunSettings(targetLength: 25, speed: 1),
        multiplier: XpMultiplierSettings(minPct: 110, maxPct: 150, curve: MultiplierCurve.gentle),
      );
      final copy = MiniGameSettings.fromMap(original.toMap());
      expect(copy.toMap(), original.toMap());
    });

    test('presets stay inside the allowed ranges', () {
      for (final p in DifficultyPreset.values) {
        final b = BalloonPopperSettings.preset(p);
        expect(BalloonPopperSettings.fromMap(b.toMap()).toMap(), b.toMap());
        final m = MatchPairsSettings.preset(p);
        expect(MatchPairsSettings.fromMap(m.toMap()).toMap(), m.toMap());
        final j = JumpAndRunSettings.preset(p);
        expect(JumpAndRunSettings.fromMap(j.toMap()).toMap(), j.toMap());
        final r = MemoryRunSettings.preset(p);
        expect(MemoryRunSettings.fromMap(r.toMap()).toMap(), r.toMap());
      }
    });

    test('jump and run course size is derived the same way as on the server', () {
      const s = JumpAndRunSettings();
      expect(s.runLength, 300);
      expect(s.collectibleCount, 12);
      expect(const JumpAndRunSettings(durationSec: 15, collectibleFrequency: 1).collectibleCount, 3);
      expect(const JumpAndRunSettings(durationSec: 90, collectibleFrequency: 3).collectibleCount, 54);
    });
  });
}
