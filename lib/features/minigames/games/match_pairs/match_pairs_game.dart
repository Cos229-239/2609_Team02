import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';
import '../../../../core/models/mini_game.dart';
import '../../mini_game_framework.dart';
import '../../widgets/game_hud.dart';
import 'match_pairs_logic.dart';

/// Game B: flip two cards at a time and find every pair.
class MatchPairsMiniGame extends MiniGameDefinition {
  const MatchPairsMiniGame();

  @override
  MiniGameId get id => MiniGameId.matchPairs;

  @override
  Widget build(BuildContext context, MiniGamePlayContext play) => MatchPairsView(play: play);
}

class MatchPairsView extends StatefulWidget {
  const MatchPairsView({super.key, required this.play});

  final MiniGamePlayContext play;

  /// How long two wrong cards stay visible.
  static const missDelay = Duration(milliseconds: 900);

  @override
  State<MatchPairsView> createState() => _MatchPairsViewState();
}

class _MatchPairsViewState extends State<MatchPairsView> {
  late final MatchPairsGame _game = MatchPairsGame.generate(widget.play.settings.matchPairs, widget.play.random);
  late final DateTime _startedAt = widget.play.clock();
  Timer? _timer;
  String? _feedback;
  bool _finished = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tap(int index) {
    final result = _game.select(index);
    if (result == PairSelection.ignored) return;
    HapticFeedback.selectionClick();
    setState(() {
      _feedback = switch (result) {
        PairSelection.match => 'Match! 🎉',
        PairSelection.miss => _game.isLost ? 'Out of misses!' : 'Not a pair - ${_game.missesLeft} left',
        _ => _feedback,
      };
    });
    if (result == PairSelection.miss) {
      _timer = Timer(MatchPairsView.missDelay, () {
        if (!mounted) return;
        if (_game.isLost) {
          _finish();
        } else {
          setState(_game.resolveMiss);
        }
      });
    } else if (_game.isWon) {
      _timer = Timer(const Duration(milliseconds: 600), _finish);
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.play.onFinished(_game.outcome(widget.play.clock().difference(_startedAt)));
  }

  @override
  Widget build(BuildContext context) {
    final hearts = List.generate(_game.maxMisses, (i) => i < _game.missesLeft ? '❤️' : '🤍').join();
    return Column(
      children: [
        GameHud(left: '🃏 ${_game.matchedPairs} / ${_game.pairs}', right: hearts),
        SizedBox(
          height: 32,
          child: Center(
            child: Text(
              _feedback ?? 'Find the pairs!',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cols = _game.columns;
              final rows = (_game.cards.length / cols).ceil();
              const gap = 10.0;
              final cellW = (constraints.maxWidth - 32 - gap * (cols - 1)) / cols;
              final cellH = (constraints.maxHeight - 16 - gap * (rows - 1)) / rows;
              final size = math.max(56.0, math.min(cellW, cellH / 1.15));
              return Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < _game.cards.length; i++)
                        SizedBox(
                          width: size,
                          height: size * 1.15,
                          child: _Card(
                            key: ValueKey('card-$i'),
                            symbol: _game.cards[i],
                            faceUp: _game.isFaceUp(i),
                            matched: _game.isMatched(i),
                            onTap: () => _tap(i),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.symbol, required this.faceUp, required this.matched, required this.onTap});

  final String symbol;
  final bool faceUp;
  final bool matched;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: faceUp ? 'Card $symbol' : 'Hidden card',
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: faceUp ? 1 : 0),
          duration: const Duration(milliseconds: 250),
          builder: (context, t, _) {
            final showFront = t >= 0.5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(math.pi * t),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(showFront ? math.pi : 0),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: showFront
                        ? (matched ? AppColors.growthGreen.withValues(alpha: 0.2) : Colors.white)
                        : const Color(0xFF7B4FD6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: matched ? AppColors.growthGreen : Colors.white, width: 3),
                    boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26, offset: Offset(0, 2))],
                  ),
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(showFront ? symbol : '?',
                          style: TextStyle(fontSize: 40, color: showFront ? null : Colors.white, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
