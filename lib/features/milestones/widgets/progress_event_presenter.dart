import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/progress_event.dart';
import '../../../core/services/milestone_service.dart';
import '../screens/approval_journey_screen.dart';

/// Wraps the child's main tabs and, when a parent has approved tasks the
/// child hasn't seen yet, shows the [ApprovalJourneyScreen] for them once.
///
/// "Once" is guaranteed by [MilestoneService.markPresented] (stored on the
/// event, so it holds across restarts and devices); this widget also never
/// presents while another route covers the tabs, while the app is in the
/// background, or while a journey is already open.
class ProgressEventPresenter extends StatefulWidget {
  const ProgressEventPresenter({super.key, required this.child, this.enabled = true, this.journeyBuilder});

  final Widget child;
  final bool enabled;

  /// Builds the journey for a batch (lets the bonus-game flow plug in).
  /// Defaults to a plain [ApprovalJourneyScreen].
  final Widget Function(BuildContext context, List<ProgressEvent> events)? journeyBuilder;

  @override
  State<ProgressEventPresenter> createState() => _ProgressEventPresenterState();
}

class _ProgressEventPresenterState extends State<ProgressEventPresenter> with WidgetsBindingObserver {
  MilestoneService? _service;
  bool _presenting = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = Provider.of<MilestoneService?>(context, listen: false);
    if (!identical(service, _service)) {
      _service?.removeListener(_schedule);
      _service = service;
      service?.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(ProgressEventPresenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service?.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    if (_scheduled || _presenting) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _maybePresent();
    });
  }

  /// Oldest events that belong together: same milestone (or none).
  static List<ProgressEvent> nextBatch(List<ProgressEvent> pending) {
    if (pending.isEmpty) return const [];
    final key = pending.first.milestoneId;
    return pending.where((e) => e.milestoneId == key).toList();
  }

  Future<void> _maybePresent() async {
    final service = _service;
    if (!mounted || !widget.enabled || service == null || _presenting) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final batch = nextBatch(service.unpresentedEvents);
    if (batch.isEmpty) return;
    // Don't cover something the child opened on top of the tabs; look again
    // shortly (popping that route doesn't notify us).
    if (ModalRoute.of(context)?.isCurrent == false) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _schedule();
      });
      return;
    }

    _presenting = true;
    final householdId = service.householdId;
    await service.markPresented(batch);
    if (!mounted || service.householdId != householdId) {
      _presenting = false;
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/family-goal/journey'),
        builder: (context) => widget.journeyBuilder?.call(context, batch) ?? ApprovalJourneyScreen(events: batch),
      ),
    );
    _presenting = false;
    if (mounted) _schedule();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
