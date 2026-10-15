import 'dart:math' as math;

import '../models/mini_game.dart';
import '../models/mini_game_settings.dart';

/// The XP a bonus game turns a task's XP into.
class XpAward {
  const XpAward({required this.baseXp, required this.multiplierPct, required this.finalXp});

  final int baseXp;

  /// 100 = 1.0×, 150 = 1.5×.
  final int multiplierPct;
  final int finalXp;

  int get bonusXp => finalXp - baseXp;

  /// "1.5×"
  String get multiplierLabel {
    final whole = multiplierPct ~/ 100;
    final frac = multiplierPct % 100;
    if (frac == 0) return '$whole×';
    final text = (multiplierPct / 100).toStringAsFixed(2);
    return '${text.endsWith('0') ? text.substring(0, text.length - 1) : text}×';
  }
}

/// The one place the mini-game XP rule lives on the client (preview only:
/// the server recomputes it in functions/src/minigames/plan.ts, with the
/// same formula and test table).
///
/// ```
/// multiplierPct = roundTo5(minPct + (maxPct − minPct) · p^curve)   // clamped 100..300
/// finalXp       = (baseXp · multiplierPct + 50) ÷ 100               // half-up
/// ```
/// Only the qualifying task's XP is multiplied; coins, board spaces and
/// household rewards never are.
class XpMultiplier {
  XpMultiplier._();

  static int multiplierPct(double performance, XpMultiplierSettings settings) {
    final p = performance.isNaN ? 0.0 : performance.clamp(0.0, 1.0);
    final min = settings.minPct.clamp(XpMultiplierSettings.hardMinPct, XpMultiplierSettings.hardMaxPct);
    final max = settings.maxPct.clamp(min, XpMultiplierSettings.hardMaxPct);
    final raw = min + (max - min) * math.pow(p, settings.curve.exponent);
    final rounded = (raw / 5).round() * 5;
    return rounded.clamp(min, max);
  }

  static int finalXp(int baseXp, int multiplierPct) {
    if (baseXp <= 0) return 0;
    return (baseXp * multiplierPct + 50) ~/ 100;
  }

  static XpAward award({required int baseXp, required double performance, required XpMultiplierSettings settings}) {
    final pct = multiplierPct(performance, settings);
    return XpAward(baseXp: baseXp, multiplierPct: pct, finalXp: finalXp(baseXp, pct));
  }
}

/// Picks the bonus game. Fair (uniform) unless parents set weights; the
/// [math.Random] is injected so tests are deterministic.
class GameSelector {
  GameSelector._();

  static MiniGameId pick(MiniGameSettings settings, math.Random random, {Iterable<MiniGameId>? available}) {
    final pool = (available ?? MiniGameId.values).toList();
    if (pool.isEmpty) throw StateError('No mini-games available');
    final weights = [for (final id in pool) settings.weightOf(id).clamp(0, 5)];
    final total = weights.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return pool[random.nextInt(pool.length)];
    var roll = random.nextInt(total);
    for (var i = 0; i < pool.length; i++) {
      if (roll < weights[i]) return pool[i];
      roll -= weights[i];
    }
    return pool.last;
  }
}
