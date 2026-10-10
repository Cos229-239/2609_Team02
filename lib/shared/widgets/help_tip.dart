import 'package:flutter/material.dart';

/// A small ⓘ icon that explains the UI element next to it. Tap it (or
/// long-press, or hover on desktop) to show a short tip; it hides itself
/// after a few seconds or on the next tap anywhere.
///
/// Built on Flutter's [Tooltip], so positioning near screen edges,
/// accessibility (the tip is exposed to screen readers) and dismissal work
/// the same on iOS and Android. Styling comes from `tooltipTheme` in
/// lib/app/theme.dart.
class HelpTip extends StatelessWidget {
  const HelpTip({
    super.key,
    required this.message,
    this.title,
    this.iconSize = 18,
    this.color,
  });

  /// One or two short sentences.
  final String message;

  /// Optional bold first line.
  final String? title;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.colorScheme.primary.withValues(alpha: 0.85);

    return Tooltip(
      richMessage: TextSpan(
        children: [
          if (title != null)
            TextSpan(
              text: '$title\n',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          TextSpan(text: message),
        ],
      ),
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      waitDuration: const Duration(milliseconds: 300),
      preferBelow: true,
      verticalOffset: 18,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      enableFeedback: true,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.info_outline, size: iconSize, color: iconColor),
      ),
    );
  }
}

/// A section heading with an optional [HelpTip] after it - the pattern used
/// for the "Needs Approval:", "Assign To:", "Reward Store" etc. headings.
class HeadingWithHelp extends StatelessWidget {
  const HeadingWithHelp({
    super.key,
    required this.heading,
    required this.help,
    this.helpTitle,
  });

  /// Usually the existing `Text(...)` heading, unchanged.
  final Widget heading;
  final String help;
  final String? helpTitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(child: heading),
        HelpTip(message: help, title: helpTitle),
      ],
    );
  }
}
