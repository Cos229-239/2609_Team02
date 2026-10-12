import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/mini_game.dart';
import '../../mini_game_framework.dart';
import '../../widgets/game_hud.dart';
import 'balloon_popper_logic.dart';

/// Game A: tap the rising balloons before time runs out.
class BalloonPopperGame extends MiniGameDefinition {
  const BalloonPopperGame();

  @override
  MiniGameId get id => MiniGameId.balloonPopper;

  @override
  Widget build(BuildContext context, MiniGamePlayContext play) => BalloonPopperView(play: play);
}

class BalloonPopperView extends StatefulWidget {
  const BalloonPopperView({super.key, required this.play});

  final MiniGamePlayContext play;

  @override
  State<BalloonPopperView> createState() => _BalloonPopperViewState();
}

class _BalloonPopperViewState extends State<BalloonPopperView> with SingleTickerProviderStateMixin {
  static const _colors = [
    Color(0xFFE5397D),
    Color(0xFF2455C9),
    Color(0xFF43A047),
    Color(0xFFFFB300),
    Color(0xFF7B4FD6),
    Color(0xFFFF7043),
  ];
  static const double _balloonSize = 72;

  late final BalloonPopperRound _round =
      BalloonPopperRound.generate(widget.play.settings.balloonPopper, widget.play.random);
  late final Ticker _ticker = createTicker(_tick);
  int _elapsedMs = 0;
  bool _done = false;

  /// Recently popped balloons, for the little "pop!" burst.
  final Map<int, (Offset, int)> _bursts = {};

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    if (_done) return;
    setState(() => _elapsedMs = elapsed.inMilliseconds);
    _bursts.removeWhere((_, v) => _elapsedMs - v.$2 > 400);
    if (_round.isOverAt(_elapsedMs)) _finish();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker.stop();
    widget.play.onFinished(_round.outcome(_elapsedMs));
  }

  void _onBalloonTap(BalloonSpec b, Offset center) {
    if (_round.pop(b.id, _elapsedMs)) {
      HapticFeedback.lightImpact();
      setState(() => _bursts[b.id] = (center, _elapsedMs));
      if (_round.isOverAt(_elapsedMs)) _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = ((_round.timeLimitMs - _elapsedMs) / 1000).ceil().clamp(0, 999);
    return Column(
      children: [
        GameHud(
          left: '🎈 ${_round.popped} / ${_round.target}',
          right: '⏱ ${remaining}s',
          progress: 1 - (_elapsedMs / _round.timeLimitMs).clamp(0.0, 1.0),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final travel = h + _balloonSize * 1.6;
              final visible = [
                for (final b in _round.visibleAt(_elapsedMs)) (b, _rectOf(b, w, h, travel)),
              ];
              // One listener for the whole sky: pops the balloon under the
              // finger on touch-down (instant feedback, no double counting).
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  for (final (b, rect) in visible.reversed) {
                    if (rect.inflate(8).contains(e.localPosition)) {
                      _onBalloonTap(b, rect.center);
                      return;
                    }
                  }
                  setState(_round.miss);
                },
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF8FD3FF), Color(0xFFE3F5FF)],
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (final (b, rect) in visible) _balloon(b, rect),
                      for (final burst in _bursts.values)
                        Positioned(
                          left: burst.$1.dx - 30,
                          top: burst.$1.dy - 30,
                          child: const IgnorePointer(child: Text('💥', style: TextStyle(fontSize: 48))),
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

  Rect _rectOf(BalloonSpec b, double w, double h, double travel) {
    final t = b.progressAt(_elapsedMs)!;
    final left = b.x * w - _balloonSize / 2;
    final top = h + _balloonSize * 0.2 - t * travel;
    return Rect.fromLTWH(left, top, _balloonSize, _balloonSize * 1.1);
  }

  Widget _balloon(BalloonSpec b, Rect rect) {
    final color = _colors[b.colorIndex % _colors.length];
    return Positioned(
      key: ValueKey('balloon-${b.id}'),
      left: rect.left,
      top: rect.top,
      width: _balloonSize,
      height: _balloonSize * 1.35,
      // Screen readers can pop a balloon with a double-tap.
      child: Semantics(
        button: true,
        label: 'Balloon',
        onTap: () => _onBalloonTap(b, rect.center),
        child: CustomPaint(painter: _BalloonPainter(color)),
      ),
    );
  }
}

class _BalloonPainter extends CustomPainter {
  _BalloonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTWH(0, 0, size.width, size.width * 1.1);
    canvas.drawOval(body, Paint()..color = color);
    canvas.drawOval(
      Rect.fromLTWH(size.width * 0.22, size.width * 0.16, size.width * 0.2, size.width * 0.28),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
    final knot = Path()
      ..moveTo(size.width * 0.45, body.bottom)
      ..lineTo(size.width * 0.55, body.bottom)
      ..lineTo(size.width * 0.5, body.bottom + 6)
      ..close();
    canvas.drawPath(knot, Paint()..color = color);
    canvas.drawLine(
      Offset(size.width * 0.5, body.bottom + 6),
      Offset(size.width * 0.5, size.height),
      Paint()
        ..color = Colors.black38
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_BalloonPainter old) => old.color != color;
}
