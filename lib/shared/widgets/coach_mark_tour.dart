import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// UI elements the spotlight tour can point at. The [MainTabShell] owns one
/// [GlobalKey] per target and hands them down through [CoachMarkScope], so
/// screens can tag an element without knowing anything about the tour.
enum CoachTarget { householdSwitcher, createTask, childProgress, navigationBar }

class CoachMarkScope extends InheritedWidget {
  const CoachMarkScope({super.key, required this.keys, required super.child});

  final Map<CoachTarget, GlobalKey> keys;

  /// The key to attach to [target], or null outside a scope (tests, or a
  /// screen pushed outside the tab shell).
  static GlobalKey? keyOf(BuildContext context, CoachTarget target) =>
      context.getInheritedWidgetOfExactType<CoachMarkScope>()?.keys[target];

  @override
  bool updateShouldNotify(CoachMarkScope oldWidget) => !identical(keys, oldWidget.keys);
}

/// One stop on the tour: a highlighted element plus a short explanation.
class CoachMark {
  const CoachMark({
    required this.title,
    required this.body,
    this.targetKey,
    this.navIndex,
    this.navCount,
    this.icon,
  });

  final String title;
  final String body;
  final IconData? icon;

  /// The element to spotlight. When null the explanation is shown centered.
  final GlobalKey? targetKey;

  /// When set, [targetKey] is a bottom [NavigationBar] and only destination
  /// [navIndex] (of [navCount] equal-width destinations) is highlighted.
  final int? navIndex;
  final int? navCount;

  Rect? resolveRect() {
    final context = targetKey?.currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    var rect = origin & box.size;
    final index = navIndex;
    final count = navCount;
    if (index != null && count != null && count > 0) {
      final width = rect.width / count;
      rect = Rect.fromLTWH(rect.left + width * index, rect.top, width, rect.height);
    }
    return rect;
  }
}

/// A dimmed overlay that spotlights one element at a time with a short
/// explanation bubble (Next / Back / Skip tour).
class CoachMarkTour {
  CoachMarkTour._();

  /// Shows [marks] over the whole app and completes when the tour is
  /// finished or skipped.
  static Future<void> show(BuildContext context, List<CoachMark> marks) {
    if (marks.isEmpty) return Future.value();
    final overlay = Overlay.of(context, rootOverlay: true);
    final completer = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CoachMarkOverlay(
        marks: marks,
        onClose: () {
          entry.remove();
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    overlay.insert(entry);
    return completer.future;
  }
}

class _CoachMarkOverlay extends StatefulWidget {
  const _CoachMarkOverlay({required this.marks, required this.onClose});

  final List<CoachMark> marks;
  final VoidCallback onClose;

  @override
  State<_CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<_CoachMarkOverlay> {
  int _index = 0;

  bool get _isLast => _index == widget.marks.length - 1;

  @override
  void initState() {
    super.initState();
    // Re-measure once the first frame with the overlay is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _next() {
    if (_isLast) {
      widget.onClose();
    } else {
      setState(() => _index++);
    }
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final mark = widget.marks[_index];
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final target = mark.resolveRect();
    final hole = target?.inflate(6);
    final ringColor = Theme.of(context).colorScheme.secondary;

    Widget bubble = _Bubble(
      mark: mark,
      index: _index,
      total: widget.marks.length,
      onNext: _next,
      onBack: _index > 0 ? _back : null,
      onSkip: widget.onClose,
    );
    bubble = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: bubble,
      ),
    );

    final Widget positionedBubble;
    if (hole == null) {
      positionedBubble = Positioned.fill(
        child: Padding(padding: const EdgeInsets.all(16), child: Center(child: bubble)),
      );
    } else if (hole.center.dy < screen.height / 2) {
      positionedBubble = Positioned(
        left: 16,
        right: 16,
        top: _clamp(hole.bottom + 14, padding.top + 8, screen.height - 200),
        child: bubble,
      );
    } else {
      positionedBubble = Positioned(
        left: 16,
        right: 16,
        bottom: _clamp(screen.height - hole.top + 14, padding.bottom + 8, screen.height - 200),
        child: bubble,
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Swallows taps so the app underneath can't be used mid-tour.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: hole),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, rect, _) => CustomPaint(
                  painter: _SpotlightPainter(
                    hole: rect,
                    color: Colors.black.withValues(alpha: 0.62),
                    ringColor: ringColor,
                  ),
                ),
              ),
            ),
          ),
          positionedBubble,
        ],
      ),
    );
  }
}

double _clamp(double value, double min, double max) {
  if (max < min) return min;
  return value < min ? min : (value > max ? max : value);
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.mark,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final CoachMark mark;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = index == total - 1;

    return Semantics(
      liveRegion: true,
      child: Material(
        color: context.raisedSurface,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (mark.icon != null) ...[
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                      child: Icon(mark.icon, size: 18, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(mark.title, style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    '${index + 1}/$total',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(mark.body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (!isLast)
                    TextButton(
                      key: const Key('coach-skip'),
                      onPressed: onSkip,
                      child: Text('Skip tour', style: TextStyle(color: Colors.grey.shade600)),
                    ),
                  const Spacer(),
                  if (onBack != null)
                    TextButton(
                      key: const Key('coach-back'),
                      onPressed: onBack,
                      child: const Text('Back'),
                    ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    key: const Key('coach-next'),
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(88, 40),
                      backgroundColor: isLast ? theme.colorScheme.secondary : theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(isLast ? 'Got it!' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.color, required this.ringColor});

  final Rect? hole;
  final Color color;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final rect = hole;
    if (rect == null) {
      canvas.drawPath(screen, Paint()..color = color);
      return;
    }
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    final cutout = Path()..addRRect(rrect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, screen, cutout),
      Paint()..color = color,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.color != color || oldDelegate.ringColor != ringColor;
}
