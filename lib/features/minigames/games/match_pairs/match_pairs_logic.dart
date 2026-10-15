import 'dart:math' as math;

import '../../../../core/models/mini_game.dart';
import '../../../../core/models/mini_game_settings.dart';

/// What a card tap did.
enum PairSelection {
  /// Not allowed right now (two cards being compared, already matched, the
  /// same card again, or the game is over).
  ignored,

  /// First card of a pair turned over.
  flipped,

  /// Second card matched the first.
  match,

  /// Second card didn't match: both turn back after [MatchPairsGame.resolveMiss].
  miss,
}

/// Match Pairs rules, pure and seeded: a shuffled deck of [pairs] pairs,
/// two cards at a time, game over after [maxMisses] wrong guesses or when
/// every pair is found.
class MatchPairsGame {
  MatchPairsGame._(this.cards, this.pairs, this.maxMisses);

  /// Picture pool; a game uses a random subset.
  static const symbols = ['🐶', '🐱', '🦊', '🐼', '🐸', '🦁', '🐵', '🐧', '🦄', '🐢', '🐙', '🦋', '🐝', '🐞'];

  factory MatchPairsGame.generate(MatchPairsSettings settings, math.Random random) {
    final picked = [...symbols]..shuffle(random);
    final chosen = picked.take(settings.pairs).toList();
    final deck = [...chosen, ...chosen]..shuffle(random);
    return MatchPairsGame._(List.unmodifiable(deck), settings.pairs, settings.maxMisses);
  }

  /// Symbol on each card, in grid order.
  final List<String> cards;
  final int pairs;
  final int maxMisses;

  final Set<int> _matched = {};
  final List<int> _faceUp = [];
  int misses = 0;
  int matchedPairs = 0;

  /// Two non-matching cards are face up, waiting for [resolveMiss].
  bool get isEvaluating => _faceUp.length == 2;

  bool get isWon => matchedPairs == pairs;
  bool get isLost => misses >= maxMisses;
  bool get isOver => isWon || isLost;
  int get missesLeft => (maxMisses - misses).clamp(0, maxMisses);

  /// Grid columns for [cards] (3 for tiny decks, else 4).
  int get columns => cards.length <= 6 ? 3 : 4;

  bool isFaceUp(int i) => _matched.contains(i) || _faceUp.contains(i);
  bool isMatched(int i) => _matched.contains(i);

  PairSelection select(int index) {
    if (isOver || isEvaluating || index < 0 || index >= cards.length) return PairSelection.ignored;
    if (_matched.contains(index) || _faceUp.contains(index)) return PairSelection.ignored;

    _faceUp.add(index);
    if (_faceUp.length == 1) return PairSelection.flipped;

    final first = _faceUp[0];
    if (cards[first] == cards[index]) {
      _matched.addAll(_faceUp);
      _faceUp.clear();
      matchedPairs++;
      return PairSelection.match;
    }
    misses++;
    return PairSelection.miss;
  }

  /// Turns the two mismatched cards back over.
  void resolveMiss() {
    if (isEvaluating) _faceUp.clear();
  }

  MiniGameOutcome outcome(Duration elapsed) => MiniGameOutcome(
        gameId: MiniGameId.matchPairs,
        details: {'matched': matchedPairs, 'pairs': pairs, 'misses': misses},
        performance: MiniGamePerformance.matchPairs(matched: matchedPairs, pairs: pairs),
        elapsed: elapsed,
        completed: isWon,
      );
}
