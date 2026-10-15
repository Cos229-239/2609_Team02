import 'dart:math' as math;

import '../../../../core/models/mini_game.dart';
import '../../../../core/models/mini_game_settings.dart';

/// One balloon: where it rises, when it appears and how long it floats.
class BalloonSpec {
  const BalloonSpec({required this.id, required this.x, required this.colorIndex, required this.appearAtMs, required this.riseMs});

  final int id;

  /// Horizontal position, 0..1 of the play area's width.
  final double x;
  final int colorIndex;
  final int appearAtMs;

  /// Time to float from the bottom to off the top (then it got away).
  final int riseMs;

  /// 0 (just appeared at the bottom) .. 1 (gone off the top), or null when
  /// not on screen at [elapsedMs].
  double? progressAt(int elapsedMs) {
    final t = (elapsedMs - appearAtMs) / riseMs;
    if (t < 0 || t >= 1) return null;
    return t;
  }
}

/// A Balloon Popper round: procedurally generated balloons (seeded), the
/// score, and the rules. Pure (no widgets/timers), so it's unit tested.
///
/// Rules: pop [target] balloons before [timeLimitMs]. More balloons than the
/// target are released, slowly, so a child doesn't need precise or rapid
/// tapping. Each balloon counts once.
class BalloonPopperRound {
  BalloonPopperRound._(this.target, this.timeLimitMs, this.balloons);

  factory BalloonPopperRound.generate(BalloonPopperSettings settings, math.Random random) {
    final target = settings.targetCount;
    final limit = settings.timeLimitSec * 1000;
    // 40% spare balloons, all released in the first 80% of the time.
    final count = (target * 1.4).ceil();
    final window = (limit * 0.8).round();
    final balloons = <BalloonSpec>[];
    var lastX = -1.0;
    for (var i = 0; i < count; i++) {
      // Even spacing plus jitter, so they don't all come at once.
      final slot = window * i / count;
      final jitter = random.nextDouble() * (window / count) * 0.8;
      var x = 0.1 + random.nextDouble() * 0.8;
      // Keep consecutive balloons apart so they don't overlap.
      if ((x - lastX).abs() < 0.18) x = x > 0.5 ? x - 0.3 : x + 0.3;
      lastX = x;
      balloons.add(BalloonSpec(
        id: i,
        x: x.clamp(0.1, 0.9),
        colorIndex: random.nextInt(colorCount),
        appearAtMs: (slot + jitter).round(),
        riseMs: 4500 + random.nextInt(2500),
      ));
    }
    return BalloonPopperRound._(target, limit, List.unmodifiable(balloons));
  }

  static const int colorCount = 6;

  final int target;
  final int timeLimitMs;
  final List<BalloonSpec> balloons;

  final Set<int> _popped = {};
  int misses = 0;
  int _endedAtMs = -1;

  int get popped => _popped.length;
  bool isPopped(int id) => _popped.contains(id);
  bool get reachedTarget => popped >= target;

  /// The round is over at [elapsedMs]: target reached or out of time.
  bool isOverAt(int elapsedMs) => reachedTarget || elapsedMs >= timeLimitMs;

  /// Balloons on screen (not popped, floating) at [elapsedMs].
  Iterable<BalloonSpec> visibleAt(int elapsedMs) =>
      balloons.where((b) => !_popped.contains(b.id) && b.progressAt(elapsedMs) != null);

  /// Taps balloon [id]. True only the first time a visible balloon is hit
  /// while the round is running; repeated taps never count twice.
  bool pop(int id, int elapsedMs) {
    if (isOverAt(elapsedMs) || id < 0 || id >= balloons.length) return false;
    if (_popped.contains(id) || balloons[id].progressAt(elapsedMs) == null) return false;
    _popped.add(id);
    return true;
  }

  /// A tap that hit no balloon (feedback only, no penalty).
  void miss() => misses++;

  MiniGameOutcome outcome(int elapsedMs) {
    if (_endedAtMs < 0) _endedAtMs = elapsedMs;
    final shown = popped > target ? target : popped;
    return MiniGameOutcome(
      gameId: MiniGameId.balloonPopper,
      details: {'popped': shown, 'target': target},
      performance: MiniGamePerformance.balloonPopper(popped: shown, target: target),
      elapsed: Duration(milliseconds: _endedAtMs),
      completed: reachedTarget,
    );
  }
}
