import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/models/mini_game.dart';
import '../../core/models/mini_game_settings.dart';
import 'games/balloon_popper/balloon_popper_game.dart';
import 'games/match_pairs/match_pairs_game.dart';

/// Everything a game gets from the host: its resolved settings, a seeded
/// random source (procedural generation is reproducible), and where to report
/// the result. Games never touch Firestore or XP themselves.
class MiniGamePlayContext {
  MiniGamePlayContext({required this.settings, required this.seed, required this.onFinished, DateTime Function()? clock})
    : random = math.Random(seed),
      clock = clock ?? DateTime.now;

  final MiniGameSettings settings;
  final int seed;
  final math.Random random;
  final DateTime Function() clock;

  /// Call exactly once when the game ends (the host ignores later calls).
  final ValueChanged<MiniGameOutcome> onFinished;
}

/// A playable mini-game: builds its widget for a [MiniGamePlayContext].
abstract class MiniGameDefinition {
  const MiniGameDefinition();

  MiniGameId get id;

  Widget build(BuildContext context, MiniGamePlayContext play);
}

/// The games this build includes. Each game registers its definition here
/// (one line per game); anything missing simply isn't offered.
class MiniGameRegistry {
  MiniGameRegistry._();

  static const List<MiniGameDefinition> definitions = <MiniGameDefinition>[
    BalloonPopperGame(),
    MatchPairsMiniGame(),
  ];

  static Iterable<MiniGameId> get ids => definitions.map((d) => d.id);

  static MiniGameDefinition? of(MiniGameId id) {
    for (final d in definitions) {
      if (d.id == id) return d;
    }
    return null;
  }
}
