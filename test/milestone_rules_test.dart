import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/family_milestone.dart';
import 'package:famotive/core/services/milestone_rules.dart';

void main() {
  final start = DateTime(2026, 10, 1);
  final end = DateTime(2026, 10, 15); // exclusive: deadline Oct 14

  FamilyMilestone milestone({
    MilestoneStatus status = MilestoneStatus.active,
    int position = 0,
    int boardLength = 20,
    int spacesPerTask = 1,
    MilestoneEligibility eligibility = const MilestoneEligibility(),
    List<String> participants = const [],
    DateTime? createdAt,
  }) =>
      FamilyMilestone(
        id: 'm1',
        title: 'Park day',
        rewardTitle: 'Amusement park',
        startsAt: start,
        endsAt: end,
        status: status,
        position: position,
        boardLength: boardLength,
        spacesPerTask: spacesPerTask,
        eligibility: eligibility,
        participantIds: participants,
        createdAt: createdAt,
      );

  ContributionDecision evaluate(
    FamilyMilestone m, {
    String? childId = 'kid',
    List<String> members = const ['parent', 'kid', 'kid2'],
    String? scheduleId,
    DateTime? completedAt,
    DateTime? approvedAt,
    bool already = false,
  }) =>
      MilestoneRules.evaluate(
        milestone: m,
        childId: childId,
        householdMemberIds: members,
        scheduleId: scheduleId,
        completedAt: completedAt ?? DateTime(2026, 10, 5, 10),
        approvedAt: approvedAt ?? DateTime(2026, 10, 5, 18),
        alreadyContributed: already,
      );

  group('MilestoneRules.evaluate', () {
    test('an eligible approval inside the window moves spacesPerTask spaces', () {
      final d = evaluate(milestone(position: 3, spacesPerTask: 2));
      expect(d.counts, isTrue);
      expect(d.from, 3);
      expect(d.to, 5);
      expect(d.spaces, 2);
    });

    test('unassigned tasks and non-members never count', () {
      expect(evaluate(milestone(), childId: null).verdict, ContributionVerdict.noChild);
      expect(evaluate(milestone(), childId: 'stranger').verdict, ContributionVerdict.noChild);
    });

    test('only listed participants count when participants are set', () {
      final m = milestone(participants: ['kid2']);
      expect(evaluate(m).verdict, ContributionVerdict.notParticipant);
      expect(evaluate(m, childId: 'kid2').counts, isTrue);
    });

    test('paused, completed and cancelled milestones never move', () {
      for (final s in [MilestoneStatus.paused, MilestoneStatus.completed, MilestoneStatus.cancelled]) {
        expect(evaluate(milestone(status: s)).verdict, ContributionVerdict.notActive, reason: s.name);
      }
    });

    test('date window: start is inclusive, end is exclusive', () {
      final m = milestone();
      expect(evaluate(m, completedAt: start, approvedAt: start).counts, isTrue);
      expect(
        evaluate(m, completedAt: start.subtract(const Duration(seconds: 1))).verdict,
        ContributionVerdict.outsideWindow,
      );
      expect(evaluate(m, completedAt: end, approvedAt: end).verdict, ContributionVerdict.outsideWindow);
      expect(
        evaluate(m, completedAt: end.subtract(const Duration(seconds: 1)), approvedAt: end).counts,
        isTrue,
      );
    });

    test('a task done before the deadline counts if approved within the 48h grace', () {
      final m = milestone();
      final doneLastDay = DateTime(2026, 10, 14, 20);
      expect(evaluate(m, completedAt: doneLastDay, approvedAt: DateTime(2026, 10, 16, 9)).counts, isTrue);
      expect(
        evaluate(m, completedAt: doneLastDay, approvedAt: end.add(FamilyMilestone.approvalGrace)).verdict,
        ContributionVerdict.approvedTooLate,
      );
    });

    test('parent-completed tasks use the approval time as completion time', () {
      final m = milestone();
      final d = MilestoneRules.evaluate(
        milestone: m,
        childId: 'kid',
        householdMemberIds: const ['kid'],
        scheduleId: null,
        completedAt: null,
        approvedAt: DateTime(2026, 9, 30),
      );
      expect(d.verdict, ContributionVerdict.outsideWindow);
    });

    test('eligibility: one-time tasks, all / selected / no repeating tasks', () {
      final noOneTime = milestone(eligibility: const MilestoneEligibility(oneTimeTasks: false));
      expect(evaluate(noOneTime).verdict, ContributionVerdict.notEligibleTask);
      expect(evaluate(noOneTime, scheduleId: 'dishes').counts, isTrue);

      final selected = milestone(
        eligibility: const MilestoneEligibility(repeating: RepeatingEligibility.selected, scheduleIds: ['dishes']),
      );
      expect(evaluate(selected, scheduleId: 'dishes').counts, isTrue);
      expect(evaluate(selected, scheduleId: 'trash').verdict, ContributionVerdict.notEligibleTask);

      final none = milestone(eligibility: const MilestoneEligibility(repeating: RepeatingEligibility.none));
      expect(evaluate(none, scheduleId: 'dishes').verdict, ContributionVerdict.notEligibleTask);
      expect(evaluate(none).counts, isTrue);
    });

    test('a task that already contributed never counts again', () {
      expect(evaluate(milestone(), already: true).verdict, ContributionVerdict.alreadyCounted);
    });

    test('progress never passes the finish', () {
      final d = evaluate(milestone(position: 19, spacesPerTask: 3));
      expect(d.to, 20);
      expect(d.spaces, 1);
      expect(evaluate(milestone(position: 20)).verdict, ContributionVerdict.boardFinished);
    });
  });

  group('MilestoneRules helpers', () {
    test('advance clamps and never goes backwards', () {
      expect(MilestoneRules.advance(0, 1, 20), 1);
      expect(MilestoneRules.advance(18, 3, 20), 20);
      expect(MilestoneRules.advance(5, -2, 20), 5);
    });

    test('recalculate sums the audit trail, capped at the board length', () {
      MilestoneContribution c(int spaces) => MilestoneContribution(
            taskId: 't$spaces',
            childId: 'kid',
            spaces: spaces,
            fromPosition: 0,
            toPosition: spaces,
            approvedAt: start,
          );
      expect(MilestoneRules.recalculate([c(1), c(2), c(3)], 20), 6);
      expect(MilestoneRules.recalculate([c(3), c(3), c(3)], 8), 8);
      expect(MilestoneRules.recalculate(const [], 8), 0);
    });

    test('pickCurrent ignores closed goals and prefers the newest', () {
      final older = milestone(createdAt: DateTime(2026, 9, 1));
      final newer = FamilyMilestone(
        id: 'm2',
        title: 'Movie night',
        rewardTitle: 'Movies',
        startsAt: start,
        endsAt: end,
        createdAt: DateTime(2026, 9, 2),
      );
      final done = milestone(status: MilestoneStatus.completed, createdAt: DateTime(2026, 9, 3));
      expect(MilestoneRules.pickCurrent([older, newer, done])!.id, 'm2');
      expect(MilestoneRules.pickCurrent([done]), isNull);
    });

    test('deadline day helpers produce local-midnight boundaries', () {
      expect(MilestoneRules.startOfDay(DateTime(2026, 10, 3, 15, 30)), DateTime(2026, 10, 3));
      expect(MilestoneRules.endOfDeadlineDay(DateTime(2026, 10, 31, 8)), DateTime(2026, 11, 1));
      expect(milestone().deadlineDay, DateTime(2026, 10, 14));
    });
  });

  group('FamilyMilestone phases', () {
    test('upcoming / active / expired are derived from the dates', () {
      final m = milestone();
      expect(m.phaseAt(DateTime(2026, 9, 30)), MilestonePhase.upcoming);
      expect(m.phaseAt(DateTime(2026, 10, 5)), MilestonePhase.active);
      expect(m.phaseAt(end), MilestonePhase.expired);
      expect(milestone(status: MilestoneStatus.paused).phaseAt(DateTime(2026, 10, 5)), MilestonePhase.paused);
      expect(milestone(status: MilestoneStatus.paused).phaseAt(end), MilestonePhase.expired);
      expect(milestone(status: MilestoneStatus.completed).phaseAt(end), MilestonePhase.completed);
      expect(milestone(status: MilestoneStatus.cancelled).phaseAt(start), MilestonePhase.cancelled);
    });

    test('fromMap clamps malformed values instead of crashing', () {
      final m = FamilyMilestone.fromMap('x', {
        'boardLength': 999,
        'position': 5000,
        'spacesPerTask': 0,
        'status': 'nonsense',
        'eligibility': 'bad',
      });
      expect(m.boardLength, FamilyMilestone.maxBoardLength);
      expect(m.position, FamilyMilestone.maxBoardLength);
      expect(m.spacesPerTask, 1);
      expect(m.status, MilestoneStatus.active);
      expect(m.eligibility.oneTimeTasks, isTrue);
    });
  });
}
