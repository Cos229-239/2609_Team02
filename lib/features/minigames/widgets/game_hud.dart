import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// The strip above every game: score on the left, timer/lives on the right,
/// and an optional time bar. Big, high-contrast text for kids.
class GameHud extends StatelessWidget {
  const GameHud({super.key, required this.left, required this.right, this.progress});

  final String left;
  final String right;

  /// 1 → 0 as time runs out; null hides the bar.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);
    return Container(
      color: context.raisedSurface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(liveRegion: true, child: Text(left, style: style))),
              Text(right, style: style),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 8,
                color: progress! > 0.25 ? AppColors.growthGreen : Colors.orange,
                backgroundColor: context.mutedFill,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
