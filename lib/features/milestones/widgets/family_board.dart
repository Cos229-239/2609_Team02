import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../board_layout.dart';

/// The family's board-game journey: a winding path of numbered spaces from
/// Start to the reward, with the family's game piece on [position].
///
/// When [animateFrom] is given (and differs from [position]) the piece hops
/// space by space from there to [position] once, then calls [onMoveDone].
class FamilyBoard extends StatefulWidget {
  const FamilyBoard({
    super.key,
    required this.boardLength,
    required this.position,
    this.animateFrom,
    this.finishIcon = '🎁',
    this.token = '👨‍👩‍👧',
    this.onMoveDone,
    this.hopDuration = const Duration(milliseconds: 420),
  });

  final int boardLength;
  final int position;
  final int? animateFrom;
  final String finishIcon;
  final String token;
  final VoidCallback? onMoveDone;
  final Duration hopDuration;

  @override
  State<FamilyBoard> createState() => _FamilyBoardState();
}

class _FamilyBoardState extends State<FamilyBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _startMove(widget.animateFrom ?? widget.position, widget.position);
  }

  @override
  void didUpdateWidget(FamilyBoard old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      // Live update (e.g. another approval while the board is open): hop
      // from wherever the piece is now.
      _startMove(_currentPosition, widget.position);
    }
  }

  double get _currentPosition => _from + (_to - _from) * _controller.value;

  void _startMove(num from, num to) {
    _from = from.toDouble().clamp(0, widget.boardLength.toDouble());
    _to = to.toDouble().clamp(0, widget.boardLength.toDouble());
    final hops = (_to - _from).abs();
    if (hops == 0) {
      _controller.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.animateFrom != null) widget.onMoveDone?.call();
      });
      return;
    }
    _controller.duration = widget.hopDuration * hops.ceil();
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) widget.onMoveDone?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        final layout = BoardLayout.compute(boardLength: widget.boardLength, width: width);
        return Semantics(
          label: 'Family board: space ${widget.position} of ${widget.boardLength}',
          child: SizedBox(
            width: layout.size.width,
            height: layout.size.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final pos = _currentPosition;
                // Small hop arc on every space crossed.
                final hopPhase = pos - pos.floorToDouble();
                final lift = _controller.isAnimating ? math.sin(hopPhase * math.pi) * layout.spaceRadius * 0.9 : 0.0;
                final point = layout.pointAt(pos);
                final tokenSize = layout.spaceRadius * 1.5;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BoardPainter(
                          layout: layout,
                          reached: pos.floor(),
                          dark: context.isDarkMode,
                        ),
                      ),
                    ),
                    // Start flag and finish reward.
                    _label(layout.centers.first, layout, '🚩', 'Start'),
                    _label(layout.centers.last, layout, widget.finishIcon, 'Goal!'),
                    Positioned(
                      left: point.dx - tokenSize / 2,
                      top: point.dy - tokenSize * 0.95 - lift,
                      width: tokenSize,
                      height: tokenSize,
                      child: IgnorePointer(
                        child: FittedBox(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primaryBlue, width: 3),
                              boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 3))],
                            ),
                            child: Text(widget.token, style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _label(Offset center, BoardLayout layout, String emoji, String text) {
    final r = layout.spaceRadius;
    return Positioned(
      left: center.dx - r * 1.4,
      top: center.dy + r * 0.55,
      width: r * 2.8,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TextStyle(fontSize: r * 0.75)),
            Text(
              text,
              maxLines: 1,
              style: TextStyle(fontSize: math.max(10, r * 0.34), fontWeight: FontWeight.w800, color: Colors.white,
                  shadows: const [Shadow(blurRadius: 3, color: Colors.black54)]),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.layout, required this.reached, required this.dark});

  final BoardLayout layout;
  final int reached;
  final bool dark;

  static const _spaceColors = [Color(0xFF2455C9), Color(0xFF43A047), Color(0xFFFFB300), Color(0xFFE5397D)];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    canvas.drawRRect(
      bg,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF1C3B2A), Color(0xFF173226)]
              : const [Color(0xFFBFE8B5), Color(0xFF8FD18A)],
        ).createShader(rect),
    );

    // Decorative bushes so it reads as a landscape, not a chart.
    final bush = Paint()..color = (dark ? const Color(0xFF24503A) : const Color(0xFF6DBE6A)).withValues(alpha: 0.6);
    final rnd = math.Random(layout.spaceCount);
    for (var i = 0; i < layout.spaceCount; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      canvas.drawCircle(Offset(dx, dy), layout.spaceRadius * (0.35 + rnd.nextDouble() * 0.3), bush);
    }

    final r = layout.spaceRadius;
    // The sandy path.
    final path = Path()..moveTo(layout.centers.first.dx, layout.centers.first.dy);
    for (final c in layout.centers.skip(1)) {
      path.lineTo(c.dx, c.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = dark ? const Color(0xFF8C7A55) : const Color(0xFFF3DFA6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 1.15
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < layout.spaceCount; i++) {
      final c = layout.centers[i];
      final isEnd = i == 0 || i == layout.spaceCount - 1;
      final base = isEnd ? const Color(0xFF7B4FD6) : _spaceColors[i % _spaceColors.length];
      final visited = i <= reached;
      canvas.drawCircle(c.translate(0, 3), r, Paint()..color = Colors.black.withValues(alpha: 0.18));
      canvas.drawCircle(c, r, Paint()..color = visited ? base : Color.lerp(base, Colors.white, 0.62)!);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      if (!isEnd) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$i',
            style: TextStyle(
              color: visited ? Colors.white : base.withValues(alpha: 0.95),
              fontWeight: FontWeight.w800,
              fontSize: r * 0.72,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.reached != reached || old.layout.size != layout.size || old.dark != dark;
}
