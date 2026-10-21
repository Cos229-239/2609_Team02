import 'mini_game.dart';

/// An integer setting with a safe range and a default. Anything missing,
/// mistyped or out of range resolves to something in range, so malformed
/// Firestore data can never crash a game.
class IntRange {
  const IntRange(this.min, this.max, this.fallback);

  final int min;
  final int max;
  final int fallback;

  int read(Object? raw) {
    if (raw is num && raw.isFinite) return raw.round().clamp(min, max);
    return fallback;
  }
}

/// Difficulty presets shown to parents instead of raw numbers.
enum DifficultyPreset { easy, normal, hard }

class BalloonPopperSettings {
  const BalloonPopperSettings({this.targetCount = 15, this.timeLimitSec = 30});

  static const targetRange = IntRange(5, 40, 15);
  static const timeRange = IntRange(15, 90, 30);

  /// Balloons to pop for the full prize.
  final int targetCount;
  final int timeLimitSec;

  static BalloonPopperSettings preset(DifficultyPreset p) => switch (p) {
        DifficultyPreset.easy => const BalloonPopperSettings(targetCount: 10, timeLimitSec: 40),
        DifficultyPreset.normal => const BalloonPopperSettings(),
        DifficultyPreset.hard => const BalloonPopperSettings(targetCount: 25, timeLimitSec: 30),
      };

  factory BalloonPopperSettings.fromMap(Map<String, dynamic> m) => BalloonPopperSettings(
        targetCount: targetRange.read(m['targetCount']),
        timeLimitSec: timeRange.read(m['timeLimitSec']),
      );

  Map<String, dynamic> toMap() => {'targetCount': targetCount, 'timeLimitSec': timeLimitSec};
}

class MatchPairsSettings {
  const MatchPairsSettings({this.pairs = 6, this.maxMisses = 3});

  static const pairsRange = IntRange(3, 10, 6);
  static const missesRange = IntRange(1, 10, 3);

  /// Number of pairs on the table (grid size follows).
  final int pairs;

  /// Wrong guesses allowed before the game ends (three by default).
  final int maxMisses;

  static MatchPairsSettings preset(DifficultyPreset p) => switch (p) {
        DifficultyPreset.easy => const MatchPairsSettings(pairs: 4, maxMisses: 4),
        DifficultyPreset.normal => const MatchPairsSettings(),
        DifficultyPreset.hard => const MatchPairsSettings(pairs: 8, maxMisses: 3),
      };

  factory MatchPairsSettings.fromMap(Map<String, dynamic> m) => MatchPairsSettings(
        pairs: pairsRange.read(m['pairs']),
        maxMisses: missesRange.read(m['maxMisses']),
      );

  Map<String, dynamic> toMap() => {'pairs': pairs, 'maxMisses': maxMisses};
}

class JumpAndRunSettings {
  const JumpAndRunSettings({this.durationSec = 30, this.obstacleDensity = 2, this.collectibleFrequency = 2});

  static const durationRange = IntRange(15, 90, 30);
  static const densityRange = IntRange(1, 3, 2);
  static const collectibleRange = IntRange(1, 3, 2);

  /// Seconds of running from start to finish line.
  final int durationSec;

  /// 1 = few obstacles, 3 = many.
  final int obstacleDensity;

  /// 1 = few stars, 3 = many.
  final int collectibleFrequency;

  /// The runner covers this many meters per second; the course is
  /// [durationSec] × this long.
  static const int metersPerSecond = 10;

  int get runLength => durationSec * metersPerSecond;

  /// Exactly how many stars a course has (the server checks this number).
  int get collectibleCount => (durationSec * collectibleFrequency ~/ 5).clamp(2, 60);

  static JumpAndRunSettings preset(DifficultyPreset p) => switch (p) {
        DifficultyPreset.easy => const JumpAndRunSettings(durationSec: 25, obstacleDensity: 1, collectibleFrequency: 3),
        DifficultyPreset.normal => const JumpAndRunSettings(),
        DifficultyPreset.hard => const JumpAndRunSettings(durationSec: 40, obstacleDensity: 3, collectibleFrequency: 2),
      };

  factory JumpAndRunSettings.fromMap(Map<String, dynamic> m) => JumpAndRunSettings(
        durationSec: durationRange.read(m['durationSec']),
        obstacleDensity: densityRange.read(m['obstacleDensity']),
        collectibleFrequency: collectibleRange.read(m['collectibleFrequency']),
      );

  Map<String, dynamic> toMap() => {
        'durationSec': durationSec,
        'obstacleDensity': obstacleDensity,
        'collectibleFrequency': collectibleFrequency,
      };
}

class MemoryRunSettings {
  const MemoryRunSettings({this.targetLength = 8, this.speed = 2});

  /// Hard cap: sequences never exceed 25 steps.
  static const maxSequenceLength = 25;
  static const lengthRange = IntRange(3, maxSequenceLength, 8);
  static const speedRange = IntRange(1, 3, 2);

  /// Sequence length that wins the maximum prize (and ends the game).
  final int targetLength;

  /// 1 = slow, 2 = normal, 3 = fast demonstration.
  final int speed;

  /// How long each step lights up during the demonstration.
  Duration get stepDuration => switch (speed) {
        1 => const Duration(milliseconds: 900),
        3 => const Duration(milliseconds: 450),
        _ => const Duration(milliseconds: 650),
      };

  static MemoryRunSettings preset(DifficultyPreset p) => switch (p) {
        DifficultyPreset.easy => const MemoryRunSettings(targetLength: 5, speed: 1),
        DifficultyPreset.normal => const MemoryRunSettings(),
        DifficultyPreset.hard => const MemoryRunSettings(targetLength: 15, speed: 3),
      };

  factory MemoryRunSettings.fromMap(Map<String, dynamic> m) => MemoryRunSettings(
        targetLength: lengthRange.read(m['targetLength']),
        speed: speedRange.read(m['speed']),
      );

  Map<String, dynamic> toMap() => {'targetLength': targetLength, 'speed': speed};
}

/// How quickly the multiplier grows with performance.
enum MultiplierCurve {
  /// Easier to earn a good bonus (p^0.7).
  gentle(0.7),

  /// Proportional (p).
  balanced(1.0),

  /// Bonus mostly for great play (p^1.5).
  challenging(1.5);

  const MultiplierCurve(this.exponent);

  final double exponent;
}

/// XP multiplier bounds, in percent (100 = 1.0×).
class XpMultiplierSettings {
  const XpMultiplierSettings({this.minPct = 100, this.maxPct = 200, this.curve = MultiplierCurve.balanced});

  /// Absolute bounds no setting can leave (the server enforces them too).
  static const hardMinPct = 100;
  static const hardMaxPct = 300;
  static const minRange = IntRange(hardMinPct, 150, 100);

  final int minPct;
  final int maxPct;
  final MultiplierCurve curve;

  factory XpMultiplierSettings.fromMap(Map<String, dynamic> m) {
    final min = minRange.read(m['minPct']);
    final max = IntRange(min, hardMaxPct, 200 < min ? min : 200).read(m['maxPct']);
    return XpMultiplierSettings(
      minPct: min,
      maxPct: max,
      curve: MultiplierCurve.values.firstWhere((c) => c.name == m['curve'], orElse: () => MultiplierCurve.balanced),
    );
  }

  Map<String, dynamic> toMap() => {'minPct': minPct, 'maxPct': maxPct, 'curve': curve.name};
}

/// Everything parents configure for mini-games: household defaults at
/// `households/{id}/miniGameSettings/household`, per-child overrides at
/// `.../miniGameSettings/{childId}`. Use [resolve] to get one child's
/// effective settings.
class MiniGameSettings {
  const MiniGameSettings({
    this.rewardedGamesEnabled = true,
    this.weights = const {},
    this.balloonPopper = const BalloonPopperSettings(),
    this.matchPairs = const MatchPairsSettings(),
    this.jumpAndRun = const JumpAndRunSettings(),
    this.memoryRun = const MemoryRunSettings(),
    this.multiplier = const XpMultiplierSettings(),
  });

  static const weightRange = IntRange(0, 5, 1);

  /// Offer a bonus game after each approved task.
  final bool rewardedGamesEnabled;

  /// Relative chance of each game being picked (default 1 each = fair).
  /// Use [weightOf]; missing games weigh 1.
  final Map<MiniGameId, int> weights;

  final BalloonPopperSettings balloonPopper;
  final MatchPairsSettings matchPairs;
  final JumpAndRunSettings jumpAndRun;
  final MemoryRunSettings memoryRun;
  final XpMultiplierSettings multiplier;

  int weightOf(MiniGameId id) => weights[id] ?? 1;

  /// Settings map of one game (as stored on a session).
  Map<String, dynamic> gameSettings(MiniGameId id) => switch (id) {
        MiniGameId.balloonPopper => balloonPopper.toMap(),
        MiniGameId.matchPairs => matchPairs.toMap(),
        MiniGameId.jumpAndRun => jumpAndRun.toMap(),
        MiniGameId.memoryRun => memoryRun.toMap(),
      };

  /// Household defaults ← child override, then every field validated.
  static MiniGameSettings resolve({Map<String, dynamic>? household, Map<String, dynamic>? child}) {
    return MiniGameSettings.fromMap(_deepMerge(household ?? const {}, child ?? const {}));
  }

  static Map<String, dynamic> _deepMerge(Map<String, dynamic> base, Map<String, dynamic> over) {
    final out = <String, dynamic>{...base};
    over.forEach((key, value) {
      final existing = out[key];
      if (value is Map && existing is Map) {
        out[key] = _deepMerge(Map<String, dynamic>.from(existing), Map<String, dynamic>.from(value));
      } else if (value != null) {
        out[key] = value;
      }
    });
    return out;
  }

  static Map<String, dynamic> _section(Object? raw) => raw is Map ? Map<String, dynamic>.from(raw) : const {};

  factory MiniGameSettings.fromMap(Map<String, dynamic> m) {
    final rawWeights = _section(m['weights']);
    final weights = <MiniGameId, int>{
      for (final id in MiniGameId.values)
        if (rawWeights.containsKey(id.name)) id: weightRange.read(rawWeights[id.name]),
    };
    // A distribution where nothing can be picked falls back to fair.
    final anyPickable = MiniGameId.values.any((id) => (weights[id] ?? 1) > 0);
    return MiniGameSettings(
      rewardedGamesEnabled: m['rewardedGamesEnabled'] is bool ? m['rewardedGamesEnabled'] as bool : true,
      weights: anyPickable ? weights : const {},
      balloonPopper: BalloonPopperSettings.fromMap(_section(m[MiniGameId.balloonPopper.name])),
      matchPairs: MatchPairsSettings.fromMap(_section(m[MiniGameId.matchPairs.name])),
      jumpAndRun: JumpAndRunSettings.fromMap(_section(m[MiniGameId.jumpAndRun.name])),
      memoryRun: MemoryRunSettings.fromMap(_section(m[MiniGameId.memoryRun.name])),
      multiplier: XpMultiplierSettings.fromMap(_section(m['multiplier'])),
    );
  }

  Map<String, dynamic> toMap() => {
        'rewardedGamesEnabled': rewardedGamesEnabled,
        'weights': {for (final id in MiniGameId.values) id.name: weightOf(id)},
        for (final id in MiniGameId.values) id.name: gameSettings(id),
        'multiplier': multiplier.toMap(),
      };

  MiniGameSettings copyWith({
    bool? rewardedGamesEnabled,
    Map<MiniGameId, int>? weights,
    BalloonPopperSettings? balloonPopper,
    MatchPairsSettings? matchPairs,
    JumpAndRunSettings? jumpAndRun,
    MemoryRunSettings? memoryRun,
    XpMultiplierSettings? multiplier,
  }) {
    return MiniGameSettings(
      rewardedGamesEnabled: rewardedGamesEnabled ?? this.rewardedGamesEnabled,
      weights: weights ?? this.weights,
      balloonPopper: balloonPopper ?? this.balloonPopper,
      matchPairs: matchPairs ?? this.matchPairs,
      jumpAndRun: jumpAndRun ?? this.jumpAndRun,
      memoryRun: memoryRun ?? this.memoryRun,
      multiplier: multiplier ?? this.multiplier,
    );
  }
}
