import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/mini_game.dart';
import '../../mini_game_framework.dart';
import '../../widgets/game_hud.dart';
import 'memory_run_logic.dart';

/// Game D: watch the buttons light up, then repeat the pattern.
class MemoryRunMiniGame extends MiniGameDefinition {
  const MemoryRunMiniGame();

  @override
  MiniGameId get id => MiniGameId.memoryRun;

  @override
  Widget build(BuildContext context, MiniGamePlayContext play) => MemoryRunView(play: play);
}

class MemoryRunView extends StatefulWidget {
  const MemoryRunView({super.key, required this.play});

  final MiniGamePlayContext play;

  /// Pads: color + a shape, so color-blind kids can play too.
  static const pads = [
    (Color(0xFF43A047), '⭐', 'Star'),
    (Color(0xFFE5397D), '❤️', 'Heart'),
    (Color(0xFF2455C9), '🔷', 'Diamond'),
    (Color(0xFFFFB300), '🌙', 'Moon'),
  ];

  @override
  State<MemoryRunView> createState() => _MemoryRunViewState();
}

class _MemoryRunViewState extends State<MemoryRunView> {
  late final MemoryRunGame _game = MemoryRunGame.generate(widget.play.settings.memoryRun, widget.play.random);
  late final Duration _step = widget.play.settings.memoryRun.stepDuration;
  late final DateTime _startedAt = widget.play.clock();
  final List<Timer> _timers = [];
  int? _lit;
  String _message = 'Watch closely...';
  bool _sound = false;
  int _replaysLeft = 1;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _after(const Duration(milliseconds: 700), _playDemo);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) {
    _timers.add(Timer(d, () {
      if (mounted) f();
    }));
  }

  /// Lights each step of the current pattern in turn, then hands over.
  void _playDemo() {
    setState(() => _message = 'Watch closely...');
    final pattern = _game.currentPattern;
    final on = Duration(milliseconds: (_step.inMilliseconds * 0.7).round());
    for (var i = 0; i < pattern.length; i++) {
      _after(_step * i, () => _light(pattern[i]));
      _after(_step * i + on, () => setState(() => _lit = null));
    }
    _after(_step * pattern.length, () {
      setState(() {
        _game.demoFinished();
        _message = 'Your turn! (${_game.round} ${_game.round == 1 ? 'step' : 'steps'})';
      });
    });
  }

  void _light(int pad) {
    if (_sound) SystemSound.play(SystemSoundType.click);
    setState(() => _lit = pad);
  }

  void _press(int pad) {
    final result = _game.press(pad);
    if (result == MemoryInput.ignored) return;
    HapticFeedback.selectionClick();
    _light(pad);
    _after(const Duration(milliseconds: 220), () => setState(() => _lit = null));
    switch (result) {
      case MemoryInput.correct:
        break;
      case MemoryInput.roundComplete:
        setState(() => _message = 'Great! Next round...');
        _after(const Duration(milliseconds: 900), () {
          _game.nextRound();
          _playDemo();
        });
      case MemoryInput.wrong:
        setState(() => _message = 'Oops! That wasn\'t it.');
        _after(const Duration(milliseconds: 1100), _finish);
      case MemoryInput.gameComplete:
        setState(() => _message = 'Amazing - you remembered it all! 🏆');
        _after(const Duration(milliseconds: 900), _finish);
      case MemoryInput.ignored:
        break;
    }
  }

  void _replay() {
    if (_replaysLeft == 0 || _game.phase != MemoryPhase.input) return;
    _replaysLeft--;
    _game.replay();
    _playDemo();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.play.onFinished(_game.outcome(widget.play.clock().difference(_startedAt)));
  }

  @override
  Widget build(BuildContext context) {
    final yourTurn = _game.phase == MemoryPhase.input;
    return Column(
      children: [
        GameHud(left: '🧠 ${_game.reached} / ${_game.target}', right: 'Round ${_game.round}'),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(_message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: yourTurn && _replaysLeft > 0 ? _replay : null,
              icon: const Icon(Icons.replay),
              label: Text('Show me again ($_replaysLeft)'),
            ),
            IconButton(
              tooltip: _sound ? 'Sound off' : 'Sound on',
              onPressed: () => setState(() => _sound = !_sound),
              icon: Icon(_sound ? Icons.volume_up : Icons.volume_off),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: AbsorbPointer(
                  // No input while the pattern is being shown.
                  absorbing: !yourTurn,
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < MemoryRunGame.padCount; i++) _pad(i),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pad(int i) {
    final (color, symbol, name) = MemoryRunView.pads[i];
    final lit = _lit == i;
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        key: ValueKey('pad-$i'),
        onTapDown: (_) => _press(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: lit ? Color.lerp(color, Colors.white, 0.45) : color.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: lit ? Colors.white : Colors.transparent, width: 6),
            boxShadow: [
              if (lit) BoxShadow(color: color, blurRadius: 24, spreadRadius: 4),
            ],
          ),
          alignment: Alignment.center,
          child: AnimatedScale(
            scale: lit ? 1.25 : 1,
            duration: const Duration(milliseconds: 120),
            child: Text(symbol, style: const TextStyle(fontSize: 48)),
          ),
        ),
      ),
    );
  }
}
