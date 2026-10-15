import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/mini_game_session.dart';
import '../../core/models/progress_event.dart';
import '../../core/services/mini_game_service.dart';
import '../milestones/screens/approval_journey_screen.dart';
import 'mini_game_framework.dart';
import 'screens/mini_game_host_screen.dart';

/// Opens the rewarded bonus game for [session] (replacing the current route
/// when [replace], so finishing returns straight to Home).
Future<void> openBonusGame(BuildContext context, MiniGameSession session, {bool replace = false}) {
  final route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/minigames/bonus'),
    builder: (_) => MiniGameHostScreen.rewarded(session: session),
  );
  final navigator = Navigator.of(context);
  return replace ? navigator.pushReplacement(route) : navigator.push(route);
}

/// The first still-playable bonus session of [events], fetched from the
/// server if the live list hasn't caught up yet.
Future<MiniGameSession?> _bonusSessionFor(MiniGameService service, List<ProgressEvent> events) async {
  for (final event in events) {
    final id = event.miniGameSessionId;
    if (id == null) continue;
    var session = service.sessionById(id);
    session ??= await service.watchSession(id).first.timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (session != null && session.canPlayAt(DateTime.now()) && MiniGameRegistry.of(session.gameId) != null) {
      return session;
    }
  }
  return null;
}

/// The child's approval journey: board move, then (if one was offered) the
/// bonus game, then back to Home. Used by [ProgressEventPresenter].
Widget buildApprovalJourney(BuildContext context, List<ProgressEvent> events) {
  final service = context.read<MiniGameService?>();
  final hasBonus = service != null && events.any((e) => e.miniGameSessionId != null);
  return ApprovalJourneyScreen(
    events: events,
    afterBoardLabel: 'Play your bonus game!',
    afterBoard: !hasBonus
        ? null
        : (journeyContext) async {
            final session = await _bonusSessionFor(service, events);
            if (!journeyContext.mounted) return;
            if (session == null) {
              ScaffoldMessenger.of(journeyContext).showSnackBar(
                const SnackBar(content: Text('That bonus game isn\'t available any more.')),
              );
              return;
            }
            unawaited(openBonusGame(journeyContext, session, replace: true));
          },
  );
}
