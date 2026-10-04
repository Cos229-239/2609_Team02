import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/task_proof.dart';

(Color, IconData) scanVerdictStyle(ScanVerdict verdict) => switch (verdict) {
      ScanVerdict.match => (Colors.green.shade700, Icons.verified_outlined),
      ScanVerdict.uncertain => (Colors.orange.shade800, Icons.help_outline),
      ScanVerdict.noMatch => (Colors.red.shade700, Icons.report_gmailerrorred),
      ScanVerdict.unclassified => (Colors.blueGrey, Icons.image_not_supported_outlined),
      ScanVerdict.unavailable => (Colors.blueGrey, Icons.visibility_outlined),
    };

class ScanVerdictBadge extends StatelessWidget {
  const ScanVerdictBadge({super.key, required this.scan, this.compact = false});

  final TaskScanResult scan;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = scanVerdictStyle(scan.verdict);
    final showScore = scan.verdict != ScanVerdict.unavailable && scan.verdict != ScanVerdict.unclassified;
    final text = showScore && !compact ? '${scan.verdict.label} · ${scan.scorePercent}' : scan.verdict.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: AppConstants.captionFontSize),
          ),
        ],
      ),
    );
  }
}
