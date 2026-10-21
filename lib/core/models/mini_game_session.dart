import 'package:cloud_firestore/cloud_firestore.dart';

import 'mini_game.dart';
import 'mini_game_settings.dart';

/// Lifecycle of a rewarded mini-game session (see
/// Documents/Family_Milestones_and_MiniGames.md, section 2).
enum MiniGameSessionStatus { offered, started, finished, rewarded, rejected, skipped, expired }

/// One rewarded bonus game, offered by a parent's task approval at
/// `households/{householdId}/miniGameSessions/{taskId}` (one per approval).
///
/// The child's app may only move it offered → started → finished (with the
/// outcome) or to skipped; the server (functions/src/minigames) validates the
/// outcome, pays the bonus once and marks it rewarded or rejected.
class MiniGameSession {
  const MiniGameSession({
    required this.id,
    required this.childId,
    required this.taskId,
    required this.gameId,
    required this.seed,
    required this.baseXp,
    required this.settings,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.taskTitle = '',
    this.attempts = 0,
    this.startedAt,
    this.finishedAt,
    this.multiplierPct,
    this.bonusXp,
    this.finalXp,
    this.rejectReason,
  });

  /// How long an offered bonus game stays playable.
  static const Duration lifetime = Duration(days: 3);

  /// Starts allowed (the second one only after an interruption).
  static const int maxAttempts = 2;

  final String id;
  final String childId;
  final String taskId;
  final String taskTitle;
  final MiniGameId gameId;

  /// Procedural generation seed (fixed at approval, so restarts don't re-roll).
  final int seed;

  /// The qualifying task's XP (already paid at approval).
  final int baseXp;

  /// Resolved settings snapshotted when offered; later setting changes never
  /// alter this session.
  final MiniGameSettings settings;

  final MiniGameSessionStatus status;
  final int attempts;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  // Server-written.
  final int? multiplierPct;
  final int? bonusXp;
  final int? finalXp;
  final String? rejectReason;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// Can be (re)started now.
  bool canPlayAt(DateTime now) =>
      !isExpiredAt(now) &&
      (status == MiniGameSessionStatus.offered ||
          (status == MiniGameSessionStatus.started && attempts < maxAttempts));

  /// Waiting for the server to pay the bonus.
  bool get isAwaitingReward => status == MiniGameSessionStatus.finished;

  /// Seed for attempt number [attempt] (1-based): a restart after an
  /// interruption gets a fresh layout but stays reproducible.
  int seedForAttempt(int attempt) => seed + (attempt - 1) * 7919;

  factory MiniGameSession.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    DateTime? time(String key) => (data[key] as Timestamp?)?.toDate();
    final created = time('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rawSettings = data['settings'];
    return MiniGameSession(
      id: doc.id,
      childId: data['childId'] as String? ?? '',
      taskId: data['taskId'] as String? ?? doc.id,
      taskTitle: data['taskTitle'] as String? ?? '',
      gameId: MiniGameId.fromName(data['gameId']) ?? MiniGameId.balloonPopper,
      seed: data['seed'] as int? ?? 0,
      baseXp: data['baseXp'] as int? ?? 0,
      settings: MiniGameSettings.fromMap(rawSettings is Map ? Map<String, dynamic>.from(rawSettings) : const {}),
      status: MiniGameSessionStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => MiniGameSessionStatus.expired,
      ),
      attempts: data['attempts'] as int? ?? 0,
      createdAt: created,
      expiresAt: time('expiresAt') ?? created.add(lifetime),
      startedAt: time('startedAt'),
      finishedAt: time('finishedAt'),
      multiplierPct: data['multiplierPct'] as int?,
      bonusXp: data['bonusXp'] as int?,
      finalXp: data['finalXp'] as int?,
      rejectReason: data['rejectReason'] as String?,
    );
  }

  /// The document a parent's approval creates.
  static Map<String, dynamic> offer({
    required String childId,
    required String taskId,
    required String taskTitle,
    required MiniGameId gameId,
    required int seed,
    required int baseXp,
    required MiniGameSettings settings,
    required DateTime now,
  }) {
    return {
      'childId': childId,
      'taskId': taskId,
      'taskTitle': taskTitle,
      'gameId': gameId.name,
      'mode': 'rewarded',
      'seed': seed,
      'baseXp': baseXp,
      'settings': settings.toMap(),
      'status': MiniGameSessionStatus.offered.name,
      'attempts': 0,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(now.add(lifetime)),
      'startedAt': null,
      'finishedAt': null,
      'outcome': null,
    };
  }
}
