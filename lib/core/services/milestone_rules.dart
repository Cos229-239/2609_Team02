import '../models/family_milestone.dart';

/// Why an approval did or didn't move a milestone board.
enum ContributionVerdict {
  counts,
  noChild,
  notParticipant,
  notActive,
  outsideWindow,
  approvedTooLate,
  notEligibleTask,
  alreadyCounted,
  boardFinished,
}

/// Result of [MilestoneRules.evaluate].
class ContributionDecision {
  const ContributionDecision(this.verdict, {this.from = 0, this.to = 0});

  final ContributionVerdict verdict;
  final int from;
  final int to;

  bool get counts => verdict == ContributionVerdict.counts;
  int get spaces => to - from;
}

/// Pure milestone contribution rules (see
/// Documents/Family_Milestones_and_MiniGames.md, section 3). Used inside the
/// approval transaction and by tests.
class MilestoneRules {
  MilestoneRules._();

  /// Decides whether a task approval moves [milestone]'s board.
  ///
  /// [completedAt] is when the child finished the task (null: parent finished
  /// it at [approvedAt]). [householdMemberIds] must contain [childId].
  static ContributionDecision evaluate({
    required FamilyMilestone milestone,
    required String? childId,
    required List<String> householdMemberIds,
    required String? scheduleId,
    required DateTime? completedAt,
    required DateTime approvedAt,
    bool alreadyContributed = false,
  }) {
    if (childId == null || !householdMemberIds.contains(childId)) {
      return const ContributionDecision(ContributionVerdict.noChild);
    }
    if (milestone.participantIds.isNotEmpty && !milestone.participantIds.contains(childId)) {
      return const ContributionDecision(ContributionVerdict.notParticipant);
    }
    if (milestone.status != MilestoneStatus.active) {
      return const ContributionDecision(ContributionVerdict.notActive);
    }
    final doneAt = completedAt ?? approvedAt;
    if (!isWithinWindow(milestone, doneAt)) {
      return const ContributionDecision(ContributionVerdict.outsideWindow);
    }
    if (approvedAt.isBefore(milestone.startsAt) ||
        !approvedAt.isBefore(milestone.endsAt.add(FamilyMilestone.approvalGrace))) {
      return const ContributionDecision(ContributionVerdict.approvedTooLate);
    }
    if (!milestone.eligibility.allows(scheduleId)) {
      return const ContributionDecision(ContributionVerdict.notEligibleTask);
    }
    if (alreadyContributed) {
      return const ContributionDecision(ContributionVerdict.alreadyCounted);
    }
    if (milestone.isFinished) {
      return const ContributionDecision(ContributionVerdict.boardFinished);
    }
    final to = advance(milestone.position, milestone.spacesPerTask, milestone.boardLength);
    return ContributionDecision(ContributionVerdict.counts, from: milestone.position, to: to);
  }

  /// [time] falls in the milestone's `[startsAt, endsAt)` window.
  static bool isWithinWindow(FamilyMilestone milestone, DateTime time) =>
      !time.isBefore(milestone.startsAt) && time.isBefore(milestone.endsAt);

  /// New position after moving [spaces] from [position]; never past the
  /// finish (no overflow) and never backwards.
  static int advance(int position, int spaces, int boardLength) {
    final next = position + (spaces < 0 ? 0 : spaces);
    return next > boardLength ? boardLength : next;
  }

  /// Position recomputed from the audit trail.
  static int recalculate(Iterable<MilestoneContribution> contributions, int boardLength) {
    var total = 0;
    for (final c in contributions) {
      total += c.spaces < 0 ? 0 : c.spaces;
    }
    return total > boardLength ? boardLength : total;
  }

  /// Picks the milestone an approval goes to: the most recently created
  /// stored-active one (there should only ever be one).
  static FamilyMilestone? pickCurrent(Iterable<FamilyMilestone> milestones) {
    FamilyMilestone? best;
    for (final m in milestones) {
      if (!m.isCurrent) continue;
      final created = m.createdAt ?? m.startsAt;
      final bestCreated = best?.createdAt ?? best?.startsAt;
      if (best == null || (bestCreated != null && created.isAfter(bestCreated))) best = m;
    }
    return best;
  }

  /// Local midnight starting [day].
  static DateTime startOfDay(DateTime day) => DateTime(day.year, day.month, day.day);

  /// Exclusive end instant for a deadline on [day]: local midnight after it.
  static DateTime endOfDeadlineDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);
}
