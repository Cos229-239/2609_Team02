import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/models/family_milestone.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/milestone_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../widgets/family_board.dart';
import '../widgets/milestone_phase_chip.dart';

/// The household's Family Goal board: where the family piece is, what moved
/// it, and (for parents) everything needed to manage the goal.
///
/// Shows [milestoneId] when given (e.g. from history), otherwise the
/// featured goal ([MilestoneService.featured]).
class FamilyBoardScreen extends StatelessWidget {
  const FamilyBoardScreen({super.key, this.milestoneId});

  final String? milestoneId;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MilestoneService>();
    final isParent = context.watch<AuthService>().currentUser?.isParent ?? false;
    final milestone = milestoneId == null ? service.featured : service.byId(milestoneId!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Goal'),
        actions: [
          if (isParent && milestone != null && milestone.isCurrent) _ParentMenu(milestone: milestone),
        ],
      ),
      body: SafeArea(
        child: !service.loaded
            ? const Center(child: CircularProgressIndicator())
            : milestone == null
                ? _EmptyState(isParent: isParent, error: service.loadError, history: service.history)
                : _BoardBody(milestone: milestone, isParent: isParent),
      ),
    );
  }
}

class _BoardBody extends StatelessWidget {
  const _BoardBody({required this.milestone, required this.isParent});

  final FamilyMilestone milestone;
  final bool isParent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.read<MilestoneService>();
    final db = context.watch<DatabaseService>();
    final phase = milestone.phaseAt(DateTime.now());
    final dates = DateFormat('MMM d');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(milestone.illustration, style: const TextStyle(fontSize: 44)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(milestone.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  MilestonePhaseChip(phase: phase),
                ],
              ),
            ),
          ],
        ),
        if (milestone.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(milestone.description, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
        AppCard(
          color: AppColors.growthGreen.withValues(alpha: 0.08),
          child: Row(
            children: [
              Text(milestone.rewardIcon, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your family is working towards:', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                    Text(milestone.rewardTitle, style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ProgressHeader(milestone: milestone),
        const SizedBox(height: 12),
        FamilyBoard(
          boardLength: milestone.boardLength,
          position: milestone.position,
          finishIcon: milestone.rewardIcon,
        ),
        const SizedBox(height: 8),
        Text(
          '${dates.format(milestone.startsAt)} – ${dates.format(milestone.deadlineDay)} · '
          '${milestone.spacesPerTask == 1 ? 'Every approved task = 1 space' : 'Every approved task = ${milestone.spacesPerTask} spaces'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        if (milestone.isCompleted)
          AppButton(
            label: milestone.isRewardClaimed ? 'See the celebration' : 'Celebrate & unlock the reward!',
            icon: Icons.celebration,
            variant: AppButtonVariant.success,
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.milestoneCelebration, arguments: milestone.id),
          ),
        if (isParent && phase == MilestonePhase.expired) ...[
          AppCard(
            color: Colors.orange.withValues(alpha: 0.1),
            child: Text(
              'Time ran out before the family reached the goal. '
              'Extend the deadline, restart from Start, or replace it with a new goal from the ⋮ menu.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        Text('Recent moves', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        StreamBuilder(
          stream: service.watchContributions(milestone.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Could not load the history right now.');
            }
            final list = snapshot.data;
            if (list == null) return const LinearProgressIndicator();
            if (list.isEmpty) {
              return Text(
                'No moves yet. Every approved task moves the family forward!',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              );
            }
            return Column(
              children: [
                for (final c in list.take(20))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.12),
                      child: Text(db.userById(c.childId)?.avatarEmoji ?? '⭐'),
                    ),
                    title: Text(c.taskTitle.isEmpty ? 'A task' : c.taskTitle),
                    subtitle: Text(
                      '${db.userById(c.childId)?.name ?? 'Family member'} · ${DateFormat('MMM d, h:mm a').format(c.approvedAt)}',
                    ),
                    trailing: Text(
                      '${c.spaces == 1 ? "+1 Space Earned!" : "+${c.spaces} Spaces Earned!"}',
                      style: const TextStyle(
                      color: AppColors.growthGreen, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
              ],
            );
          },
        ),
        if (service.history.isNotEmpty && milestone.isCurrent) ...[
          const SizedBox(height: 16),
          _HistoryList(history: service.history),
        ],
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.milestone});

  final FamilyMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${milestone.position} of ${milestone.boardLength} spaces',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              milestone.isFinished ? 'Goal reached! 🎉' : '${milestone.spacesLeft} to go',
              style: theme.textTheme.titleSmall?.copyWith(color: AppColors.growthGreen),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: milestone.progress,
            minHeight: 10,
            color: AppColors.growthGreen,
            backgroundColor: AppColors.growthGreen.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.history});

  final List<FamilyMilestone> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Past goals', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final m in history.take(10))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(m.illustration, style: const TextStyle(fontSize: 26)),
            title: Text(m.title),
            subtitle: Text('${m.position} of ${m.boardLength} spaces'),
            trailing: MilestonePhaseChip(phase: m.phaseAt(DateTime.now()), compact: true),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.familyBoard, arguments: m.id),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isParent, required this.error, required this.history});

  final bool isParent;
  final String? error;
  final List<FamilyMilestone> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Center(child: Text('🗺️', style: TextStyle(fontSize: 72))),
        const SizedBox(height: 12),
        Text(
          error ?? 'No family goal yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          isParent
              ? 'Pick something fun to do together - a movie night, a park day - and every approved task moves the family closer.'
              : 'Ask a parent to start a family goal. Every task you finish will move the whole family closer to a fun reward!',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        if (isParent)
          AppButton(
            label: 'Create a Family Goal',
            icon: Icons.flag,
            variant: AppButtonVariant.success,
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.milestoneEditor),
          ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 24),
          _HistoryList(history: history),
        ],
      ],
    );
  }
}

enum _Action { edit, pause, resume, extend, complete, restart, replace, cancel, recalculate }

class _ParentMenu extends StatelessWidget {
  const _ParentMenu({required this.milestone});

  final FamilyMilestone milestone;

  Future<void> _run(BuildContext context, _Action action) async {
    final service = context.read<MilestoneService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    Future<bool> confirm(String title, String body, String ok) async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ok)),
          ],
        ),
      );
      return result == true;
    }

    Future<DateTime?> pickDeadline() {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final initial = milestone.deadlineDay.isBefore(today) ? today.add(const Duration(days: 7)) : milestone.deadlineDay;
      return showDatePicker(
        context: context,
        helpText: 'New deadline',
        initialDate: initial,
        firstDate: today,
        lastDate: today.add(const Duration(days: 366)),
      );
    }

    try {
      switch (action) {
        case _Action.edit:
          await navigator.pushNamed(AppRoutes.milestoneEditor, arguments: milestone.id);
        case _Action.pause:
          await service.pause(milestone.id);
          messenger.showSnackBar(const SnackBar(content: Text('Paused - approvals won\'t move the board until you resume.')));
        case _Action.resume:
          await service.resume(milestone.id);
        case _Action.extend:
          final day = await pickDeadline();
          if (day != null) await service.extend(milestone.id, day);
        case _Action.complete:
          if (await confirm('Finish the goal now?', 'The family reward unlocks right away.', 'Finish')) {
            await service.completeNow(milestone.id);
          }
        case _Action.restart:
          final day = await pickDeadline();
          if (day == null) break;
          if (await confirm('Restart from Start?', 'This goal is kept in history and a fresh copy starts today.', 'Restart')) {
            await service.restart(milestone.id, startDay: DateTime.now(), deadlineDay: day);
          }
        case _Action.replace:
          if (await confirm('Replace this goal?', 'It\'s kept in history and you can create a new one.', 'Replace')) {
            await service.replace(milestone.id);
            await navigator.pushNamed(AppRoutes.milestoneEditor);
          }
        case _Action.cancel:
          if (await confirm('Cancel this goal?', 'The board stops and no reward unlocks. History is kept.', 'Cancel goal')) {
            await service.cancel(milestone.id);
          }
        case _Action.recalculate:
          final position = await service.recalculate(milestone.id);
          messenger.showSnackBar(SnackBar(content: Text('Board recalculated: space $position.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final paused = milestone.status == MilestoneStatus.paused;
    return PopupMenuButton<_Action>(
      tooltip: 'Manage family goal',
      onSelected: (a) => _run(context, a),
      itemBuilder: (context) => [
        const PopupMenuItem(value: _Action.edit, child: Text('Edit goal')),
        if (paused)
          const PopupMenuItem(value: _Action.resume, child: Text('Resume'))
        else
          const PopupMenuItem(value: _Action.pause, child: Text('Pause')),
        const PopupMenuItem(value: _Action.extend, child: Text('Change deadline')),
        const PopupMenuItem(value: _Action.complete, child: Text('Finish now & unlock reward')),
        const PopupMenuItem(value: _Action.restart, child: Text('Restart from Start')),
        const PopupMenuItem(value: _Action.replace, child: Text('Replace with a new goal')),
        const PopupMenuItem(value: _Action.recalculate, child: Text('Recalculate progress')),
        const PopupMenuItem(value: _Action.cancel, child: Text('Cancel goal')),
      ],
    );
  }
}
