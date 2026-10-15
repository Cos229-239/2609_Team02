import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/mini_game_settings.dart';
import 'package:famotive/features/minigames/games/match_pairs/match_pairs_game.dart';
import 'package:famotive/features/minigames/games/match_pairs/match_pairs_logic.dart';
import 'package:famotive/features/minigames/mini_game_framework.dart';

void main() {
  const settings = MatchPairsSettings(pairs: 6, maxMisses: 3);

  MatchPairsGame game([int seed = 1, MatchPairsSettings s = settings]) => MatchPairsGame.generate(s, math.Random(seed));

  /// Index of the other card with the same symbol.
  int partnerOf(MatchPairsGame g, int i) =>
      [for (var j = 0; j < g.cards.length; j++) j].firstWhere((j) => j != i && g.cards[j] == g.cards[i]);

  /// A card that does NOT match card [i].
  int strangerOf(MatchPairsGame g, int i, {Set<int> avoid = const {}}) =>
      [for (var j = 0; j < g.cards.length; j++) j]
          .firstWhere((j) => j != i && g.cards[j] != g.cards[i] && !g.isMatched(j) && !avoid.contains(j));

  group('MatchPairsGame.generate', () {
    test('every symbol appears exactly twice; layouts are seeded', () {
      for (final pairs in [3, 6, 10]) {
        final g = game(4, MatchPairsSettings(pairs: pairs));
        expect(g.cards.length, pairs * 2);
        final counts = <String, int>{};
        for (final c in g.cards) {
          counts[c] = (counts[c] ?? 0) + 1;
        }
        expect(counts.length, pairs);
        expect(counts.values.every((n) => n == 2), isTrue);
      }
      expect(game(9).cards, game(9).cards);
      expect(game(9).cards, isNot(game(10).cards));
    });

    test('grid size follows the number of pairs', () {
      expect(game(1, const MatchPairsSettings(pairs: 3)).columns, 3);
      expect(game(1, const MatchPairsSettings(pairs: 8)).columns, 4);
    });
  });

  group('MatchPairsGame rules', () {
    test('two cards at a time: a match stays up, a miss turns back over', () {
      final g = game();
      expect(g.select(0), PairSelection.flipped);
      expect(g.select(partnerOf(g, 0)), PairSelection.match);
      expect(g.isMatched(0), isTrue);
      expect(g.matchedPairs, 1);

      final a = strangerOf(g, 0);
      expect(g.select(a), PairSelection.flipped);
      final b = strangerOf(g, a);
      expect(g.select(b), PairSelection.miss);
      expect(g.misses, 1);
      expect(g.isEvaluating, isTrue);
      expect(g.isFaceUp(a) && g.isFaceUp(b), isTrue);
      g.resolveMiss();
      expect(g.isFaceUp(a) || g.isFaceUp(b), isFalse);
    });

    test('extra taps while two cards are being compared are ignored', () {
      final g = game();
      final a = strangerOf(g, 0, avoid: {});
      g.select(0);
      g.select(strangerOf(g, 0));
      expect(g.isEvaluating, isTrue);
      expect(g.select(a == 0 ? 1 : a), PairSelection.ignored);
      expect(g.select(partnerOf(g, 0)), PairSelection.ignored);
      expect(g.misses, 1, reason: 'no extra misses counted');
    });

    test('accidental double taps and matched cards are ignored', () {
      final g = game();
      expect(g.select(0), PairSelection.flipped);
      expect(g.select(0), PairSelection.ignored);
      expect(g.select(partnerOf(g, 0)), PairSelection.match);
      expect(g.select(0), PairSelection.ignored);
      expect(g.select(-1), PairSelection.ignored);
      expect(g.select(99), PairSelection.ignored);
    });

    test('the game ends after exactly three misses and can\'t be bypassed', () {
      final g = game();
      for (var i = 0; i < 3; i++) {
        final a = strangerOf(g, 0);
        g.select(0);
        expect(g.select(a), PairSelection.miss);
        if (i < 2) {
          expect(g.isOver, isFalse);
          expect(g.missesLeft, 2 - i);
        }
        g.resolveMiss();
      }
      expect(g.isLost, isTrue);
      expect(g.missesLeft, 0);
      expect(g.select(partnerOf(g, 0)), PairSelection.ignored);
      expect(g.select(0), PairSelection.ignored);
      final o = g.outcome(const Duration(seconds: 10));
      expect(o.details, {'matched': 0, 'pairs': 6, 'misses': 3});
      expect(o.performance, 0);
      expect(o.completed, isFalse);
    });

    test('matching every pair wins with the actual counts', () {
      final g = game(2);
      // One wrong guess first.
      g.select(0);
      g.select(strangerOf(g, 0));
      g.resolveMiss();
      final done = <int>{};
      for (var i = 0; i < g.cards.length; i++) {
        if (done.contains(i)) continue;
        final p = partnerOf(g, i);
        g.select(i);
        g.select(p);
        done.addAll([i, p]);
      }
      expect(g.isWon, isTrue);
      final o = g.outcome(const Duration(seconds: 20));
      expect(o.details, {'matched': 6, 'pairs': 6, 'misses': 1});
      expect(o.performance, 1);
      expect(o.completed, isTrue);
    });
  });

  testWidgets('playing through the UI: misses shown as hearts, game reports once', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final reports = <MiniGameOutcome>[];
    final play = MiniGamePlayContext(
      settings: const MiniGameSettings(matchPairs: MatchPairsSettings(pairs: 3, maxMisses: 1)),
      seed: 5,
      onFinished: reports.add,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => const MatchPairsMiniGame().build(c, play)))));
    expect(find.text('🃏 0 / 3'), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);

    final g = MatchPairsGame.generate(play.settings.matchPairs, math.Random(5));
    final wrong = [for (var j = 1; j < g.cards.length; j++) j].firstWhere((j) => g.cards[j] != g.cards[0]);
    await tester.tap(find.byKey(const ValueKey('card-0')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('card-$wrong')));
    await tester.pump();
    expect(find.text('Out of misses!'), findsOneWidget);
    // Taps while the cards are shown are ignored.
    await tester.tap(find.byKey(const ValueKey('card-1')));
    await tester.pump(MatchPairsView.missDelay);
    await tester.pump(const Duration(milliseconds: 300));
    expect(reports, hasLength(1));
    expect(reports.single.details, {'matched': 0, 'pairs': 3, 'misses': 1});
  });

  test('Match Pairs is registered with the framework', () {
    expect(MiniGameRegistry.of(MiniGameId.matchPairs), isA<MatchPairsMiniGame>());
  });
}
