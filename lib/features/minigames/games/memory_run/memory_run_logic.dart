import 'dart:math' as math;

import '../../../../core/models/mini_game.dart';
import '../../../../core/models/mini_game_settings.dart';

enum MemoryPhase {
  /// The pattern is being shown; input is blocked.
  demo,

  /// The child repeats the pattern.
  input,

  /// Round repeated correctly; the next (one step longer) is coming.
  roundWon,

  /// Wrong button: the game is over.
  failed,

  /// The full target sequence was repeated.
  completed,
}

enum MemoryInput { ignored, correct, roundComplete, wrong, gameComplete }

/// Simon-says rules, pure and seeded. Round `r` shows the first `r` steps of
/// one random [sequence]; the game ends on a wrong button or after the
/// target round.
class MemoryRunGame {
  MemoryRunGame._(this.sequence);

  /// Validates the target before a session begins: 1..25 steps.
  factory MemoryRunGame.generate(MemoryRunSettings settings, math.Random random) {
    final target = settings.targetLength;
    if (target < 1 || target > MemoryRunSettings.maxSequenceLength) {
      throw ArgumentError.value(target, 'targetLength', 'must be 1..${MemoryRunSettings.maxSequenceLength}');
    }
    return MemoryRunGame._(List.unmodifiable([for (var i = 0; i < target; i++) random.nextInt(padCount)]));
  }

  static const int padCount = 4;

  final List<int> sequence;

  int round = 1;
  int _inputIndex = 0;
  MemoryPhase phase = MemoryPhase.demo;

  int get target => sequence.length;

  /// Rounds fully repeated (what the score is based on).
  int get reached => switch (phase) {
        MemoryPhase.completed => target,
        MemoryPhase.roundWon => round,
        _ => round - 1,
      };

  /// The steps shown in the current round.
  List<int> get currentPattern => sequence.sublist(0, round);

  int get inputIndex => _inputIndex;
  bool get isOver => phase == MemoryPhase.failed || phase == MemoryPhase.completed;

  /// The demonstration finished; the child may answer.
  void demoFinished() {
    if (phase == MemoryPhase.demo) {
      phase = MemoryPhase.input;
      _inputIndex = 0;
    }
  }

  /// One button press; ignored unless it's the child's turn.
  MemoryInput press(int pad) {
    if (phase != MemoryPhase.input || pad < 0 || pad >= padCount) return MemoryInput.ignored;
    if (sequence[_inputIndex] != pad) {
      phase = MemoryPhase.failed;
      return MemoryInput.wrong;
    }
    _inputIndex++;
    if (_inputIndex < round) return MemoryInput.correct;
    if (round == target) {
      phase = MemoryPhase.completed;
      return MemoryInput.gameComplete;
    }
    phase = MemoryPhase.roundWon;
    return MemoryInput.roundComplete;
  }

  /// Starts the next, one step longer round (shows its demo first).
  void nextRound() {
    if (phase != MemoryPhase.roundWon) return;
    round++;
    _inputIndex = 0;
    phase = MemoryPhase.demo;
  }

  /// "Show me again": replays the current round's pattern.
  void replay() {
    if (phase == MemoryPhase.input) {
      phase = MemoryPhase.demo;
      _inputIndex = 0;
    }
  }

  MiniGameOutcome outcome(Duration elapsed) => MiniGameOutcome(
        gameId: MiniGameId.memoryRun,
        details: {'reached': reached, 'target': target},
        performance: MiniGamePerformance.memoryRun(reached: reached, target: target),
        elapsed: elapsed,
        completed: phase == MemoryPhase.completed,
      );
}
