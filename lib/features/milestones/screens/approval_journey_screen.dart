import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/models/progress_event.dart';
import '../../../core/services/milestone_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/family_board.dart';

/// Shown to a child after a parent approves their task(s): "Task approved!",
/// then the family piece hops from where it was to where it is now, then the
/// celebration if that reached the goal. Pushed once per batch of events by
/// [ProgressEventPresenter].
///
/// [afterBoard] lets the caller continue the journey (the bonus mini-game)
/// once the board has been shown; it gets this screen's context.
class ApprovalJourneyScreen extends StatefulWidget {
  const ApprovalJourneyScreen({super.key, required this.events, this.afterBoard, this.afterBoardLabel});

  /// Events of one milestone, oldest first.
  final List<ProgressEvent> events;

  final Future<void> Function(BuildContext context)? afterBoard;

  /// Button label for [afterBoard], e.g. "Play your bonus game!".
  final String? afterBoardLabel;

  @override
  State<ApprovalJourneyScreen> createState() => _ApprovalJourneyScreenState();
}

class _ApprovalJourneyScreenState extends State<ApprovalJourneyScreen> {
  /// Events that moved the board (an approval can also only offer a bonus game).
  late final List<ProgressEvent> _boardEvents = widget.events.where((e) => e.movedBoard).toList();
  late bool _moved = _boardEvents.isEmpty;

  ProgressEvent get _first => _boardEvents.first;
  ProgressEvent get _last => _boardEvents.last;

  int get _from {
    var from = _first.fromPosition ?? 0;
    for (final e in _boardEvents) {
      if (e.fromPosition != null && e.fromPosition! < from) from = e.fromPosition!;
    }
    return from;
  }

  int get _to {
    var to = _last.toPosition ?? 0;
    for (final e in _boardEvents) {
      if (e.toPosition != null && e.toPosition! > to) to = e.toPosition!;
    }
    return to;
  }

  bool get _completed => _boardEvents.any((e) => e.milestoneCompleted);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBoard = _boardEvents.isNotEmpty;
    final milestone = !hasBoard ? null : context.watch<MilestoneService?>()?.byId(_first.milestoneId!);
    final boardLength = !hasBoard ? 0 : (milestone?.boardLength ?? _last.boardLength ?? _to);
    final spaces = !hasBoard ? 0 : _to - _from;
    final titles = widget.events.map((e) => e.taskTitle).where((t) => t.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task approved!'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('🎉', textAlign: TextAlign.center, style: const TextStyle(fontSize: 56)),
            Text(
              widget.events.length == 1 ? 'Great job!' : '${widget.events.length} tasks approved!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            if (titles.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                titles.length <= 2
                    ? titles.join(' and ')
                    : '${titles.take(2).join(', ')} and ${titles.length - 2} more',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
            if (hasBoard) ...[
              const SizedBox(height: 12),
              AnimatedOpacity(
                opacity: _moved ? 1 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: Text(
                  spaces <= 0
                      ? 'Your family is at the goal!'
                      : 'Your family moved $spaces ${spaces == 1 ? 'space' : 'spaces'} closer to '
                            '${milestone?.rewardTitle ?? _first.milestoneTitle ?? 'the reward'}!',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: AppColors.growthGreen),
                ),
              ),
              const SizedBox(height: 12),
              FamilyBoard(
                boardLength: boardLength,
                position: _to,
                animateFrom: _from,
                finishIcon: milestone?.rewardIcon ?? '🎁',
                onMoveDone: () {
                  if (mounted) setState(() => _moved = true);
                },
              ),
              const SizedBox(height: 8),
              Text('$_to of $boardLength spaces', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            ],
            const SizedBox(height: 20),
            if (_completed) ...[
              AppButton(
                label: 'We reached the goal! Celebrate 🎉',
                variant: AppButtonVariant.success,
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.milestoneCelebration, arguments: _first.milestoneId),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.afterBoard != null) ...[
              AppButton(
                key: const Key('journey-continue'),
                label: widget.afterBoardLabel ?? 'Continue',
                icon: Icons.sports_esports,
                variant: AppButtonVariant.primary,
                onPressed: _moved ? () => widget.afterBoard!(context) : null,
              ),
              const SizedBox(height: 12),
            ],
            AppButton(
              key: const Key('journey-done'),
              label: widget.afterBoard != null ? 'Maybe later' : 'Back to Home',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
