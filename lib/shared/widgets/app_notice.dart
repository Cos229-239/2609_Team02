import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// How a notice is coloured.
enum NoticeTone { info, success, error }

/// Centre-screen notice card used instead of SnackBars: an emoji (or tone
/// icon) in a bubble, the message, and an optional action. One at a time,
/// queued; tap the card to dismiss, otherwise it fades after a few seconds.
/// Taps outside the card go through to the screen underneath.
///
/// ```dart
/// showAppNotice(context, '"Make Bed" created!', tone: NoticeTone.success);
///
/// final notices = AppNotice.of(context); // safe to keep across an await
/// await save();
/// notices.show('Saved.');
/// ```
class AppNotice {
  AppNotice._(this._overlay);

  /// Captures the app's root overlay, so the notice still shows after the
  /// calling screen is popped.
  static AppNotice of(BuildContext context) => AppNotice._(Overlay.of(context, rootOverlay: true));

  /// For code without a screen context (e.g. a service holding the
  /// navigator key): `AppNotice.on(navigatorKey.currentState!.overlay!)`.
  factory AppNotice.on(OverlayState overlay) => AppNotice._(overlay);

  final OverlayState _overlay;

  static final Queue<_Notice> _queue = Queue();
  static OverlayEntry? _current;

  void show(
    String message, {
    NoticeTone? tone,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;
    if (_queue.isNotEmpty && _queue.last.message == text) return; // rapid repeats
    _queue.add(_Notice(text, tone ?? NoticeTone.info, actionLabel, onAction, duration));
    while (_queue.length > 3) {
      _queue.removeFirst();
    }
    // The overlay that held the last notice may be gone (app restarted,
    // tests): don't let a stale entry block the queue.
    if (_current != null && !_current!.mounted) _current = null;
    if (_current == null) _next(_overlay);
  }

  /// Removes the notice on screen and anything queued.
  static void clear() {
    _queue.clear();
    _current?.remove();
    _current = null;
  }

  static void _next(OverlayState overlay) {
    if (_queue.isEmpty || !overlay.mounted) {
      _current = null;
      return;
    }
    final notice = _queue.removeFirst();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NoticeCard(
        notice: notice,
        onDone: () {
          if (_current != entry) return;
          entry.remove();
          _current = null;
          _next(overlay);
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

/// Shorthand for `AppNotice.of(context).show(...)`.
void showAppNotice(
  BuildContext context,
  String message, {
  NoticeTone? tone,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) =>
    AppNotice.of(context).show(message, tone: tone, actionLabel: actionLabel, onAction: onAction, duration: duration);

class _Notice {
  _Notice(this.message, this.tone, this.actionLabel, this.onAction, this.duration);

  final String message;
  final NoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration? duration;
}

bool _isEmoji(int r) =>
    (r >= 0x1F000 && r <= 0x1FAFF) || (r >= 0x2600 && r <= 0x27BF) || (r >= 0x2B00 && r <= 0x2BFF) ||
    (r >= 0x2300 && r <= 0x23FF) || (r >= 0x2190 && r <= 0x21FF);

/// A leading emoji (with its variation selector, skin tone or ZWJ joins)
/// becomes the card's icon: returns (emoji, rest of the message) or null.
(String, String)? _splitLeadingEmoji(String text) {
  final runes = text.runes.toList();
  if (runes.isEmpty || !_isEmoji(runes.first)) return null;
  var i = 1;
  while (i < runes.length) {
    final r = runes[i];
    if (r == 0xFE0F || (r >= 0x1F3FB && r <= 0x1F3FF)) {
      i++;
    } else if (r == 0x200D && i + 1 < runes.length) {
      i += 2;
    } else {
      break;
    }
  }
  return (String.fromCharCodes(runes.take(i)), String.fromCharCodes(runes.skip(i)).trimLeft());
}

class _NoticeCard extends StatefulWidget {
  const _NoticeCard({required this.notice, required this.onDone});

  final _Notice notice;
  final VoidCallback onDone;

  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final Duration _showFor;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final n = widget.notice;
    _showFor = n.duration ??
        Duration(milliseconds: (1800 + n.message.length * 40).clamp(2200, n.actionLabel != null ? 6000 : 4500));
    _anim.forward();
    _timer = Timer(_showFor, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) await _anim.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Color _color(bool dark) => switch (widget.notice.tone) {
        NoticeTone.success => dark ? AppColors.growthGreenDark : AppColors.growthGreen,
        NoticeTone.error => const Color(0xFFF08A00),
        NoticeTone.info => dark ? AppColors.primaryBlueDark : AppColors.primaryBlue,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = _color(dark);
    final n = widget.notice;
    final split = _splitLeadingEmoji(n.message);
    final emoji = split?.$1;
    final body = split?.$2 ?? n.message;

    final icon = emoji != null
        ? Text(emoji, style: const TextStyle(fontSize: 30, height: 1.1))
        : Icon(
            switch (n.tone) {
              NoticeTone.success => Icons.check_rounded,
              NoticeTone.error => Icons.priority_high_rounded,
              NoticeTone.info => Icons.info_outline_rounded,
            },
            color: Colors.white,
            size: 32,
          );

    final card = Container(
      margin: const EdgeInsets.only(top: 30),
      padding: EdgeInsets.fromLTRB(20, 38, 20, n.actionLabel != null ? 12 : 22),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDarkRaised : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            body.isEmpty ? n.message : body,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
          ),
          if (n.actionLabel != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: () {
                n.onAction?.call();
                _close();
              },
              child: Text(n.actionLabel!),
            ),
          ],
          const SizedBox(height: 10),
          // Time left before it fades.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: _showFor,
            builder: (_, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: Container(height: 4, decoration: BoxDecoration(color: color.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4))),
            ),
          ),
        ],
      ),
    );

    final bubble = Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: dark ? AppColors.surfaceDarkRaised : Colors.white, width: 4),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: icon,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn),
            child: FadeTransition(
              opacity: _anim,
              child: Semantics(
                liveRegion: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: GestureDetector(
                    onTap: _close,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      children: [card, Positioned(top: 0, child: bubble)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
