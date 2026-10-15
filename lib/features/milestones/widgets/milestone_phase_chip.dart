import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/family_milestone.dart';

/// Small colored pill naming a milestone's [MilestonePhase].
class MilestonePhaseChip extends StatelessWidget {
  const MilestonePhaseChip({super.key, required this.phase, this.compact = false});

  final MilestonePhase phase;
  final bool compact;

  static (String, Color) describe(MilestonePhase phase) => switch (phase) {
        MilestonePhase.upcoming => ('Starts soon', Colors.indigo),
        MilestonePhase.active => ('In progress', AppColors.primaryBlue),
        MilestonePhase.paused => ('Paused', Colors.blueGrey),
        MilestonePhase.expired => ('Time\'s up', Colors.orange.shade800),
        MilestonePhase.completed => ('Completed', AppColors.growthGreen),
        MilestonePhase.cancelled => ('Cancelled', Colors.grey.shade700),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = describe(phase);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: compact ? 11 : 12),
      ),
    );
  }
}
