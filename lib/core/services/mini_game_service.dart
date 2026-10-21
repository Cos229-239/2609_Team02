import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/mini_game.dart';
import '../models/mini_game_session.dart';
import '../models/mini_game_settings.dart';
import '../models/user.dart';

/// Mini-game sessions and settings of the active household.
///
/// Children: their rewarded bonus games ([openSessions]) and the session
/// lifecycle ([start], [finish], [skip]). Parents: household defaults and
/// per-child overrides ([saveHouseholdSettings], [saveChildOverride]).
///
/// The bonus XP itself is only ever paid by the server
/// (functions/src/minigames); nothing here writes XP.
class MiniGameService extends ChangeNotifier {
  MiniGameService({FirebaseFirestore? firestore, DateTime Function()? clock})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _clock = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _clock;

  String? _householdId;
  AppUser? _user;

  /// The signed-in child's sessions (any status), newest first.
  List<MiniGameSession> sessions = [];

  /// Raw `miniGameSettings/household` (null: not set → defaults).
  Map<String, dynamic>? householdSettingsRaw;

  /// Raw per-child overrides by child id.
  Map<String, Map<String, dynamic>> childOverridesRaw = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sessionsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _settingsSub;

  String? get householdId => _householdId;

  DocumentReference<Map<String, dynamic>> get _householdRef =>
      _firestore.collection('households').doc(_householdId);

  CollectionReference<Map<String, dynamic>> get _sessionsRef => _householdRef.collection('miniGameSessions');
  CollectionReference<Map<String, dynamic>> get _settingsRef => _householdRef.collection('miniGameSettings');

  void bind(AppUser? user) {
    final householdId = user?.householdId;
    final same = householdId == _householdId && user?.id == _user?.id;
    _user = user;
    if (same) return;

    unawaited(_sessionsSub?.cancel());
    unawaited(_settingsSub?.cancel());
    _sessionsSub = null;
    _settingsSub = null;
    _householdId = householdId;
    sessions = [];
    householdSettingsRaw = null;
    childOverridesRaw = {};
    notifyListeners();
    if (householdId == null || user == null) return;

    _settingsSub = _settingsRef.snapshots().listen((snap) {
      householdSettingsRaw = null;
      childOverridesRaw = {};
      for (final doc in snap.docs) {
        if (doc.id == 'household') {
          householdSettingsRaw = doc.data();
        } else {
          childOverridesRaw[doc.id] = doc.data();
        }
      }
      notifyListeners();
    }, onError: (Object e) => debugPrint('MiniGameService: settings listener error: $e'));

    if (user.isChild) {
      _sessionsSub = _sessionsRef.where('childId', isEqualTo: user.id).snapshots().listen((snap) {
        sessions = snap.docs.map(MiniGameSession.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        notifyListeners();
      }, onError: (Object e) => debugPrint('MiniGameService: sessions listener error: $e'));
    }
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  // --- Queries -----------------------------------------------------------

  /// Bonus games the child can play right now, oldest first.
  List<MiniGameSession> get openSessions {
    final now = _clock();
    return sessions.where((s) => s.canPlayAt(now)).toList().reversed.toList(growable: false);
  }

  MiniGameSession? sessionById(String id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Stream<MiniGameSession?> watchSession(String id) =>
      _sessionsRef.doc(id).snapshots().map((s) => s.exists ? MiniGameSession.fromFirestore(s) : null);

  /// Household defaults (validated).
  MiniGameSettings get householdSettings => MiniGameSettings.resolve(household: householdSettingsRaw);

  /// [childId]'s effective settings: defaults ← household ← child override.
  MiniGameSettings settingsFor(String childId) =>
      MiniGameSettings.resolve(household: householdSettingsRaw, child: childOverridesRaw[childId]);

  bool hasOverride(String childId) => childOverridesRaw.containsKey(childId);

  // --- Child: session lifecycle -----------------------------------------------

  void _requireOwnSession(MiniGameSession session) {
    final user = _user;
    if (user == null || user.id != session.childId) {
      throw Exception('This bonus game belongs to someone else.');
    }
  }

  /// Starts (or, after an interruption, restarts) a rewarded session.
  /// Returns the attempt number (1-based), which picks the layout seed.
  ///
  /// A transaction on purpose: a rewarded game has to *start* online, so the
  /// server's `startedAt` is real play time (the server checks the game took
  /// a plausible time). Finishing may happen offline. The Firestore rules
  /// only allow offered→started / started→started with `attempts` going up
  /// by one (at most [MiniGameSession.maxAttempts]).
  Future<int> start(MiniGameSession session) async {
    _requireOwnSession(session);
    final ref = _sessionsRef.doc(session.id);
    try {
      return await _firestore.runTransaction<int>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('This bonus game is no longer available.');
        final stored = MiniGameSession.fromFirestore(snap);
        final now = _clock();
        if (!stored.canPlayAt(now)) {
          throw Exception(
            stored.isExpiredAt(now) ? 'This bonus game has expired.' : 'This bonus game was already played.',
          );
        }
        final attempt = stored.attempts + 1;
        tx.update(ref, {
          'status': MiniGameSessionStatus.started.name,
          'attempts': attempt,
          'startedAt': FieldValue.serverTimestamp(),
        });
        return attempt;
      }).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw Exception('Bonus games need an internet connection to start. Try again when you\'re online!');
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        throw Exception('Bonus games need an internet connection to start. Try again when you\'re online!');
      }
      rethrow;
    }
  }

  /// Reports the result. The server validates it and pays the bonus once.
  /// Works offline: the write is queued and the server sees it later.
  Future<void> finish(MiniGameSession session, MiniGameOutcome outcome) async {
    _requireOwnSession(session);
    await _sessionsRef.doc(session.id).update({
      'status': MiniGameSessionStatus.finished.name,
      'outcome': outcome.toMap(),
      'finishedAt': FieldValue.serverTimestamp(),
    });
  }

  /// No bonus for this one (the task's own XP is kept).
  Future<void> skip(MiniGameSession session) async {
    _requireOwnSession(session);
    await _sessionsRef.doc(session.id).update({'status': MiniGameSessionStatus.skipped.name});
  }

  // --- Parent: settings --------------------------------------------------------

  void _requireParent() {
    if (_user == null || !_user!.isParent || _householdId == null) {
      throw Exception('Only a parent can change mini-game settings.');
    }
  }

  Future<void> saveHouseholdSettings(MiniGameSettings settings) async {
    _requireParent();
    await _settingsRef.doc('household').set({
      ...MiniGameSettings.fromMap(settings.toMap()).toMap(),
      'updatedBy': _user!.id,
      'updatedAt': Timestamp.fromDate(_clock()),
    });
  }

  /// Saves [childId]'s own settings, or removes the override (null) so the
  /// household defaults apply again. Sessions already offered keep the
  /// settings they were offered with.
  Future<void> saveChildOverride(String childId, MiniGameSettings? settings) async {
    _requireParent();
    final ref = _settingsRef.doc(childId);
    if (settings == null) {
      await ref.delete();
      return;
    }
    await ref.set({
      ...MiniGameSettings.fromMap(settings.toMap()).toMap(),
      'updatedBy': _user!.id,
      'updatedAt': Timestamp.fromDate(_clock()),
    });
  }
}
