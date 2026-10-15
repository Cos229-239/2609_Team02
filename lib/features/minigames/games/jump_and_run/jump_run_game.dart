import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/mini_game.dart';
import '../../mini_game_framework.dart';
import '../../widgets/game_hud.dart';
import 'jump_run_logic.dart';

/// Game C: a side-scrolling run - tap to jump over obstacles and grab stars.
class JumpAndRunMiniGame extends MiniGameDefinition {
  const JumpAndRunMiniGame();

  @override
  MiniGameId get id => MiniGameId.jumpAndRun;

  @override
  Widget build(BuildContext context, MiniGamePlayContext play) => JumpRunView(play: play);
}

class JumpRunView extends StatefulWidget {
  const JumpRunView({super.key, required this.play});

  final MiniGamePlayContext play;

  @override
  State<JumpRunView> createState() => _JumpRunViewState();
}

class _JumpRunViewState extends State<JumpRunView> with SingleTickerProviderStateMixin {
  late final JumpRunSim _sim = JumpRunSim(JumpRunCourse.generate(widget.play.settings.jumpAndRun, widget.play.random));
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  bool _done = false;

  /// Short "3, 2, 1" before the run so nobody is caught off guard.
  static const _countdown = Duration(seconds: 2);
  Duration _elapsed = Duration.zero;

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
    _elapsed = elapsed;
    if (elapsed < _countdown) {
      setState(() {});
      _last = elapsed;
      return;
    }
    // Small fixed sub-steps; a slow frame slows the game rather than
    // teleporting the runner through an obstacle.
    var dt = math.min((elapsed - _last).inMicroseconds / 1e6, 1 / 20);
    _last = elapsed;
    final hearts = _sim.hearts;
    while (dt > 0 && !_sim.isOver) {
      final step = math.min(dt, 1 / 120);
      _sim.step(step);
      dt -= step;
    }
    if (_sim.hearts < hearts) HapticFeedback.mediumImpact();
    setState(() {});
    if (_sim.isOver) {
      _done = true;
      _ticker.stop();
      widget.play.onFinished(_sim.outcome(elapsed - _countdown));
    }
  }

  void _jump() {
    if (_elapsed < _countdown) return;
    _sim.jump();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_sim.x / _sim.course.runLength * 100).floor();
    final hearts = List.generate(JumpRunSim.startingHearts, (i) => i < _sim.hearts ? '❤️' : '🤍').join();
    final counting = _elapsed < _countdown;
    return Column(
      children: [
        GameHud(
          left: '⭐ ${_sim.collected.length} / ${_sim.course.collectibles.length}',
          right: hearts,
          progress: 1 - _sim.x / _sim.course.runLength,
        ),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Tap to jump',
            child: GestureDetector(
              key: const Key('jump-area'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _jump(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RunPainter(sim: _sim, dark: Theme.of(context).brightness == Brightness.dark),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 12,
                    child: Text('$percent%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                  if (counting)
                    Center(
                      child: Text(
                        '${(_countdown - _elapsed).inSeconds + 1}',
                        style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w900, color: Colors.white,
                            shadows: [Shadow(blurRadius: 8, color: Colors.black45)]),
                      ),
                    )
                  else if (_sim.time < 2.5)
                    const Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Text('Tap anywhere to jump!', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white,
                              shadows: [Shadow(blurRadius: 4, color: Colors.black54)])),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RunPainter extends CustomPainter {
  _RunPainter({required this.sim, required this.dark});

  final JumpRunSim sim;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // Portrait phones: keep the action in the middle and show ~18 m of
    // course (about 1.5 s of warning before an obstacle arrives).
    final groundY = size.height * 0.62;
    final ppm = math.min(size.width / 18, size.height / 6); // horizontal pixels per meter
    // Drawn taller than the physics scale so sprites are big enough for kids
    // on a narrow phone; widths (what collisions use) stay true to scale.
    final ppmY = math.min(ppm * 2.2, groundY / 4);
    final runnerScreenX = size.width * 0.18;
    double sx(double worldX) => runnerScreenX + (worldX - sim.x) * ppm;
    double sy(double worldY) => groundY - worldY * ppmY;

    // Sky and parallax hills.
    final sky = Offset.zero & size;
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF1B2A4A), Color(0xFF2E4A6E)] : const [Color(0xFF7EC8FF), Color(0xFFD8F0FF)],
        ).createShader(sky),
    );
    final cloud = Paint()..color = Colors.white.withValues(alpha: dark ? 0.15 : 0.8);
    for (var i = -1; i < 5; i++) {
      final cx = (i * 160 - (sim.x * ppm * 0.15) % 160).toDouble() + 40;
      final cy = groundY * (0.2 + 0.15 * (i % 2));
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: 90, height: 34), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + 22, cy - 12), width: 50, height: 34), cloud);
    }
    final hill = Paint()..color = dark ? const Color(0xFF29523A) : const Color(0xFF9ED39A);
    for (var i = -1; i < 6; i++) {
      final hx = (i * 220 - (sim.x * ppm * 0.3) % 220).toDouble();
      canvas.drawCircle(Offset(hx, groundY + 40), 120, hill);
    }
    // Ground with moving stripes.
    canvas.drawRect(Rect.fromLTRB(0, groundY, size.width, size.height), Paint()..color = const Color(0xFF6DBE45));
    canvas.drawRect(Rect.fromLTRB(0, groundY + 10, size.width, size.height), Paint()..color = const Color(0xFFA0703C));
    final stripe = Paint()..color = const Color(0xFF8D5F2F);
    for (var m = (sim.x - 20).floorToDouble(); m < sim.x + 20; m += 2) {
      canvas.drawRect(Rect.fromLTWH(sx(m), groundY + 18, ppm * 0.6, 6), stripe);
    }
    // Finish flag.
    final fx = sx(sim.course.runLength);
    if (fx < size.width + 40) {
      canvas.drawRect(Rect.fromLTWH(fx, sy(3), 4, 3 * ppmY), Paint()..color = Colors.white);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 4; c++) {
          canvas.drawRect(
            Rect.fromLTWH(fx + 4 + c * 8, sy(3) + r * 8, 8, 8),
            Paint()..color = (r + c).isEven ? Colors.black : Colors.white,
          );
        }
      }
    }

    // Obstacles (friendly bushes/crates).
    for (final o in sim.course.obstacles) {
      final left = sx(o.x);
      if (left > size.width || left + o.width * ppm < 0) continue;
      final rect = Rect.fromLTRB(left, sy(o.height), left + o.width * ppm, groundY);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()..color = const Color(0xFFB5651D));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(4)),
        Paint()
          ..color = const Color(0xFF8B4513)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Stars.
    for (final c in sim.course.collectibles) {
      if (sim.collected.contains(c.id)) continue;
      final cx = sx(c.x);
      if (cx < -20 || cx > size.width + 20) continue;
      _star(canvas, Offset(cx, sy(c.y)), ppmY * 0.32);
    }

    // The runner: a round, friendly character facing right.
    // Flickers after a hit, but never disappears completely.
    final blink = sim.isInvulnerable && (sim.time * 10).floor().isEven;
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: blink ? 0.35 : 1));
    {
      final h = JumpPhysics.runnerHeight * ppmY;
      final bodyCenter = Offset(runnerScreenX, sy(sim.y) - h * 0.45);
      final legPhase = math.sin(sim.time * 18) * (sim.onGround ? 1 : 0);
      final leg = Paint()
        ..color = const Color(0xFF1A1E27)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(bodyCenter + Offset(-6, h * 0.3), Offset(runnerScreenX - 6 + legPhase * 6, sy(sim.y)), leg);
      canvas.drawLine(bodyCenter + Offset(6, h * 0.3), Offset(runnerScreenX + 6 - legPhase * 6, sy(sim.y)), leg);
      canvas.drawCircle(bodyCenter, h * 0.38, Paint()..color = const Color(0xFF2455C9));
      canvas.drawCircle(bodyCenter + Offset(h * 0.14, -h * 0.08), h * 0.11, Paint()..color = Colors.white);
      canvas.drawCircle(bodyCenter + Offset(h * 0.18, -h * 0.08), h * 0.05, Paint()..color = Colors.black);
      canvas.drawArc(
        Rect.fromCenter(center: bodyCenter + Offset(h * 0.1, h * 0.08), width: h * 0.25, height: h * 0.15),
        0,
        math.pi,
        false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    canvas.restore();
  }

  void _star(Canvas canvas, Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * radius, math.sin(a) * radius);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFC107));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE09A00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RunPainter old) => true;
}
