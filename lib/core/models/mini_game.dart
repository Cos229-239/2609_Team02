import 'package:flutter/material.dart';

/// The four reward mini-games. The `name` is what's stored in Firestore
/// (`miniGameSessions.gameId`, settings keys) and in functions/src/minigames.
enum MiniGameId {
  balloonPopper(
    title: 'Balloon Popper',
    emoji: '🎈',
    blurb: 'Pop the balloons before time runs out!',
    howToPlay: 'Tap each balloon to pop it. Pop as many as you can before the timer ends.',
    color: Color(0xFFE5397D),
  ),
  matchPairs(
    title: 'Match Pairs',
    emoji: '🃏',
    blurb: 'Flip cards and find the matching pairs.',
    howToPlay: 'Tap two cards to flip them. Find every pair - but watch out, you only have a few misses!',
    color: Color(0xFF7B4FD6),
  ),
  jumpAndRun(
    title: 'Jump and Run',
    emoji: '🏃',
    blurb: 'Run, jump over obstacles and grab the stars.',
    howToPlay: 'Tap anywhere to jump. Hop over the obstacles and collect stars until you reach the finish.',
    color: Color(0xFF43A047),
  ),
  memoryRun(
    title: 'Memory Run',
    emoji: '🧠',
    blurb: 'Watch the pattern, then repeat it.',
    howToPlay: 'Watch the buttons light up, then tap them in the same order. Each round adds one more step!',
    color: Color(0xFF2455C9),
  );

  const MiniGameId({
    required this.title,
    required this.emoji,
    required this.blurb,
    required this.howToPlay,
    required this.color,
  });

  final String title;
  final String emoji;
  final String blurb;
  final String howToPlay;
  final Color color;

  static MiniGameId? fromName(Object? name) {
    for (final id in values) {
      if (id.name == name) return id;
    }
    return null;
  }
}

/// What one game session produced. [details] are the game's own counters
/// (e.g. `popped`/`target`), which are what's sent to the server; the server
/// recomputes [performance] from them (see functions/src/minigames/plan.ts).
class MiniGameOutcome {
  const MiniGameOutcome({
    required this.gameId,
    required this.details,
    required this.performance,
    required this.elapsed,
    this.completed = false,
  });

  final MiniGameId gameId;

  /// Integer counters only (validated server-side).
  final Map<String, int> details;

  /// 0..1, see [MiniGamePerformance].
  final double performance;

  final Duration elapsed;

  /// The child reached the game's target (all pairs, full sequence, finish line...).
  final bool completed;

  Map<String, dynamic> toMap() => {
        'details': details,
        'completed': completed,
        'elapsedMs': elapsed.inMilliseconds,
      };
}

/// Each game's score → performance `p ∈ [0, 1]`. The single client-side
/// definition; functions/src/minigames/plan.ts mirrors it exactly.
class MiniGamePerformance {
  MiniGamePerformance._();

  static double _ratio(int part, int whole) {
    if (whole <= 0) return 0;
    final r = part / whole;
    return r < 0 ? 0 : (r > 1 ? 1 : r);
  }

  static double balloonPopper({required int popped, required int target}) => _ratio(popped, target);

  static double matchPairs({required int matched, required int pairs}) => _ratio(matched, pairs);

  /// Distance counts most; collectibles add the rest (a run with no
  /// collectibles on the course counts them as all collected).
  static double jumpAndRun({
    required int distance,
    required int runLength,
    required int collected,
    required int collectibles,
  }) {
    final d = _ratio(distance, runLength);
    final c = collectibles <= 0 ? 1.0 : _ratio(collected, collectibles);
    return 0.7 * d + 0.3 * c;
  }

  static double memoryRun({required int reached, required int target}) => _ratio(reached, target);
}
