import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/models/mini_game.dart';
import '../../core/models/mini_game_session.dart';
import '../../core/models/mini_game_settings.dart';
import '../../core/models/task.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/database_service.dart';
import '../../core/services/kid_mode.dart';
import '../../core/services/mini_game_service.dart';
import '../../core/services/xp_multiplier.dart';
import '../../shared/widgets/parent_verification.dart';
import '../tasks/task_completion_flow.dart';

/// Rex's Room: the child's 3D voxel pet game (games/rex, bundled into
/// assets/rex/index.html), hosted in a full-screen WebView.
///
/// The child's real tasks are pushed in with `RexGame.setTasks` whenever the
/// database changes. When the child taps "Done!" in the game it posts
/// `taskCompleted`, and we run the normal [startTaskCompletion] flow (photo
/// proof included), so approvals still go through a parent. Rex's needs,
/// in-game coins and items are saved in the WebView, one slot per child.
///
/// Rex shares the child's level: the game shows the child's real XP
/// (`RexGame.setPlayer`). The four minigames run in the WebView too; bonus
/// sessions are started and finished through [MiniGameService] exactly as
/// the old host screen did, so the server still validates and pays the XP.
/// [launchSessionId] opens straight into that bonus game.
///
/// Kid mode: a parent opens Rex for one of their children ([childId]) on
/// the parent's own device (Progress tab) and hands it over. The child plays
/// and does their tasks as usual (submitted for approval like any other
/// completion), but can't leave: the back button, the back swipe and the
/// game's own close button all ask for [ParentVerification] first (Face ID
/// / Touch ID, or the math parental gate). Bonus
/// games stay with the child's own login (the server only accepts their
/// results from the child), so kid mode offers practice games only.
class RexRoomScreen extends StatefulWidget {
  const RexRoomScreen({super.key, this.launchSessionId, this.childId});

  final String? launchSessionId;

  /// The child to play as. Null: the signed-in child.
  final String? childId;

  static const String _asset = 'assets/rex/index.html';
  // Gives the page a stable origin so its localStorage save survives.
  static const String _baseUrl = 'https://rex.famotive.app/';
  static const Color _background = Color(0xFF1B2A55);

  @override
  State<RexRoomScreen> createState() => _RexRoomScreenState();
}

class _RexRoomScreenState extends State<RexRoomScreen> {
  late final WebViewController _controller;
  late final DatabaseService _db;
  late final AuthService _auth;
  MiniGameService? _games;
  String? _childId;
  String? _lastGamesJson;
  int? _lastXp;
  bool _autoLaunched = false;
  bool _ready = false;
  bool _loadStarted = false;
  String? _lastTasksJson;
  EdgeInsets? _insets;

  /// A parent handed their device to [_childId]: leaving needs the gate.
  bool _kidMode = false;
  bool _gateOpen = false;

  @override
  void initState() {
    super.initState();
    _db = context.read<DatabaseService>();
    _auth = context.read<AuthService>();
    _games = context.read<MiniGameService?>();
    final me = _auth.currentUser;
    _childId = widget.childId ?? me?.id;
    _kidMode = widget.childId != null && widget.childId != me?.id;
    if (_kidMode) KidMode.active.value = true;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(RexRoomScreen._background)
      // Kids Category (guideline 1.3): the game is a bundled page and must
      // never navigate a child out to the web.
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) => _isBundledPage(request.url)
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ))
      ..addJavaScriptChannel('FamotiveBridge', onMessageReceived: _onMessage);
    _db.addListener(_pushTasks);
    _db.addListener(_pushPlayer);
    _games?.addListener(_pushGames);
    _auth.addListener(_pushPlayer);
  }

  static bool _isBundledPage(String url) =>
      url.startsWith(RexRoomScreen._baseUrl) ||
      url.startsWith('about:') ||
      url.startsWith('data:') ||
      url.startsWith('blob:');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The WebView doesn't see the notch / home indicator itself, so the
    // page gets the device's safe-area padding from here (and again on
    // every rotation).
    final insets = MediaQuery.viewPaddingOf(context);
    if (insets == _insets) return;
    _insets = insets;
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    } else if (_ready) {
      _controller.runJavaScript('window.RexGame && RexGame.setInsets(${jsonEncode(_insetsJson)});');
    }
  }

  Map<String, double> get _insetsJson {
    final i = _insets ?? EdgeInsets.zero;
    return {'top': i.top, 'right': i.right, 'bottom': i.bottom, 'left': i.left};
  }

  @override
  void dispose() {
    if (_kidMode) KidMode.active.value = false;
    _db.removeListener(_pushTasks);
    _db.removeListener(_pushPlayer);
    _games?.removeListener(_pushGames);
    _auth.removeListener(_pushPlayer);
    super.dispose();
  }

  Future<void> _load() async {
    final html = await rootBundle.loadString(RexRoomScreen._asset);
    final config = jsonEncode({'player': _childId ?? '', 'insets': _insetsJson});
    await _controller.loadHtmlString(
      html.replaceFirst('<head>', '<head><script>window.REX_EMBED = $config;</script>'),
      baseUrl: RexRoomScreen._baseUrl,
    );
  }

  List<TaskModel> get _tasks {
    final id = _childId;
    if (id == null) return const [];
    return _db.tasksForUser(id).where((t) => !t.isUpcoming && !t.isStaleDone).toList();
  }

  void _pushTasks() {
    if (!_ready || !mounted) return;
    final json = jsonEncode([
      for (final t in _tasks)
        {
          'id': t.id,
          'title': t.title,
          'icon': _emojiFor(t.icon),
          'rewardXp': t.rewardXp,
          'coinReward': t.coinReward,
          // pending | completed | approved: the same names the game uses.
          'status': t.status.name,
          // Photo proof (Premium): the game shows a camera button, and the
          // app's TaskProofScreen opens when the child taps it.
          'needsPhoto': _db.needsPhoto(t),
          'photoSent': t.proof != null,
          'photoCheck': t.proofNeedsReview,
          'care': ?_careFor(t.icon),
        },
    ]);
    if (json == _lastTasksJson) return;
    _lastTasksJson = json;
    _controller.runJavaScript('window.RexGame && RexGame.setTasks($json);');
  }

  void _js(String code) => _controller.runJavaScript('window.RexGame && $code');

  /// The child's total XP: Rex shows the same level.
  void _pushPlayer() {
    if (!_ready || !mounted) return;
    final id = _childId;
    final xp = _kidMode ? (id == null ? null : _db.userById(id)?.xp) : _auth.currentUser?.xp;
    if (xp == null || xp == _lastXp) return;
    _lastXp = xp;
    _js('RexGame.setPlayer(${jsonEncode({'xp': xp})});');
  }

  MiniGameSettings get _settings {
    final id = _childId;
    return id == null || _games == null ? const MiniGameSettings() : _games!.settingsFor(id);
  }

  /// Open bonus sessions + the child's settings (for practice rounds).
  void _pushGames() {
    if (!_ready || !mounted) return;
    final json = jsonEncode({
      'enabled': _settings.rewardedGamesEnabled,
      'settings': _settings.toMap(),
      'bonus': [
        if (!_kidMode)
          for (final s in _games?.openSessions ?? const <MiniGameSession>[])
            {'sessionId': s.id, 'gameId': s.gameId.name, 'taskTitle': s.taskTitle, 'baseXp': s.baseXp},
      ],
    });
    if (json == _lastGamesJson) return;
    _lastGamesJson = json;
    _js('RexGame.setGames($json);');
    _maybeAutoLaunch();
  }

  void _launch(Map<String, Object?> payload) => _js('RexGame.launchGame(${jsonEncode(payload)});');

  /// `startGame`: a bonus session goes through [MiniGameService.start]
  /// (online, counts an attempt); practice just gets the child's settings.
  Future<void> _startGame(String? gameName, String? sessionId) async {
    final gameId = MiniGameId.fromName(gameName);
    if (gameId == null) return _launch({'ok': false, 'error': 'Unknown game.'});
    if (sessionId == null) {
      return _launch({
        'ok': true,
        'gameId': gameId.name,
        'sessionId': null,
        'seed': math.Random().nextInt(1 << 31),
        'settings': _settings.toMap(),
      });
    }
    final session = _games?.sessionById(sessionId);
    if (session == null || !session.canPlayAt(DateTime.now())) {
      return _launch({'ok': false, 'error': 'That bonus game isn\'t available any more.'});
    }
    try {
      final attempt = await _games!.start(session);
      _launch({
        'ok': true,
        'gameId': session.gameId.name,
        'sessionId': session.id,
        'seed': session.seedForAttempt(attempt),
        'settings': session.settings.toMap(),
        'baseXp': session.baseXp,
        'taskTitle': session.taskTitle,
        'attempt': attempt,
      });
    } catch (e) {
      _launch({'ok': false, 'error': e.toString().replaceFirst('Exception: ', '')});
    }
  }

  /// `gameFinished`: report a bonus result (queued if offline); the server
  /// validates it and pays the XP. The game gets the preview to show.
  Future<void> _finishGame(Map<dynamic, dynamic> msg) async {
    final sessionId = msg['sessionId'];
    final gameId = MiniGameId.fromName(msg['gameId']);
    if (sessionId is! String || gameId == null) return;
    final session = _games?.sessionById(sessionId);
    if (session == null) return;
    final raw = msg['details'];
    final details = <String, int>{
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value is num) '${e.key}': (e.value as num).round(),
    };
    final performance = _performance(gameId, details);
    final outcome = MiniGameOutcome(
      gameId: gameId,
      details: details,
      performance: performance,
      elapsed: Duration(milliseconds: (msg['elapsedMs'] as num?)?.round() ?? 0),
      completed: msg['completed'] == true,
    );
    final award = XpMultiplier.award(baseXp: session.baseXp, performance: performance, settings: session.settings.multiplier);
    _js('RexGame.gameResult(${jsonEncode({'multiplierPct': award.multiplierPct, 'finalXp': award.finalXp})});');
    unawaited(_games!.finish(session, outcome).catchError((Object e) {
      debugPrint('RexRoom: could not report result: $e');
    }));
  }

  double _performance(MiniGameId id, Map<String, int> d) => switch (id) {
        MiniGameId.balloonPopper => MiniGamePerformance.balloonPopper(popped: d['popped'] ?? 0, target: d['target'] ?? 0),
        MiniGameId.matchPairs => MiniGamePerformance.matchPairs(matched: d['matched'] ?? 0, pairs: d['pairs'] ?? 0),
        MiniGameId.jumpAndRun => MiniGamePerformance.jumpAndRun(
            distance: d['distance'] ?? 0,
            runLength: d['runLength'] ?? 0,
            collected: d['collected'] ?? 0,
            collectibles: d['collectibles'] ?? 0,
          ),
        MiniGameId.memoryRun => MiniGamePerformance.memoryRun(reached: d['reached'] ?? 0, target: d['target'] ?? 0),
      };

  /// Opened from a bonus prompt: go straight into that game once ready.
  void _maybeAutoLaunch() {
    final id = widget.launchSessionId;
    if (id == null || _autoLaunched || _kidMode) return;
    final session = _games?.sessionById(id);
    if (session == null) return;
    _autoLaunched = true;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _js('RexGame.chooseGame(${jsonEncode(session.gameId.name)}, ${jsonEncode(session.id)});');
    });
  }

  Future<void> _onMessage(JavaScriptMessage message) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } on FormatException {
      return;
    }
    if (decoded is! Map || !mounted) return;
    switch (decoded['type']) {
      case 'ready':
        _ready = true;
        _lastTasksJson = null;
        _lastGamesJson = null;
        _lastXp = null;
        _pushTasks();
        _pushPlayer();
        _pushGames();
        _maybeAutoLaunch();
        // In case the device rotated while the page was loading.
        _controller.runJavaScript('RexGame.setInsets(${jsonEncode(_insetsJson)});');
      case 'taskCompleted':
        final id = decoded['taskId'];
        TaskModel? task;
        for (final t in _tasks) {
          if (t.id == id && t.status == TaskStatus.pending) task = t;
        }
        if (task != null) await startTaskCompletion(context, task);
        // Re-sync either way: a cancelled photo proof puts the task back to
        // "To Do" in the game.
        _lastTasksJson = null;
        _pushTasks();
      case 'startGame':
        final sessionId = decoded['sessionId'];
        await _startGame(decoded['gameId'] as String?, sessionId is String ? sessionId : null);
      case 'gameFinished':
        await _finishGame(decoded);
      case 'skipGame':
        final session = _games?.sessionById('${decoded['sessionId']}');
        if (session != null) unawaited(_games!.skip(session).catchError((Object e) => debugPrint('RexRoom: skip failed: $e')));
      case 'close':
        if (!mounted) return;
        if (_kidMode) {
          await _leaveKidMode();
        } else {
          Navigator.of(context).maybePop();
        }
    }
  }

  /// Kid mode: only a grown-up can close Rex: Face ID / Touch ID, or the
  /// math gate when that isn't available or doesn't work.
  Future<void> _leaveKidMode() async {
    if (_gateOpen) return;
    _gateOpen = true;
    final passed = await ParentVerification.verify(
      context,
      reason: "Parent check to leave Rex's Room",
      gateReason: "Leaving Rex's Room needs a grown-up. Parents: answer to go back to your account.",
    );
    _gateOpen = false;
    if (passed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Kid mode blocks the Android back button and the iOS back swipe; the
      // parent check decides instead (Navigator.pop below isn't affected by this).
      canPop: !_kidMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _kidMode) _leaveKidMode();
      },
      child: Scaffold(
        backgroundColor: RexRoomScreen._background,
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}

/// Task icon keys (see TaskIconCatalog) → emoji shown in the game.
String _emojiFor(String key) => const {
      'bed': '🛏️', 'cleaning': '🧹', 'trash': '🗑️', 'laundry': '🧺',
      'dishes': '🍽️', 'table': '🍴', 'homework': '✏️', 'reading': '📚',
      'pet': '🐶', 'plant': '🪴', 'yard': '🌳', 'shopping': '🛒',
      'errand': '🏃', 'bike': '🚲', 'music': '🎵', 'art': '🎨',
      'game': '🎮', 'gift': '🎁', 'star': '⭐', 'outside': '☀️', 'food': '🥕',
    }[key] ??
    '✅';

/// Which of Rex's needs a task helps. Null lets the game guess from the title.
String? _careFor(String key) => const {
      'bed': 'energy', 'homework': 'energy', 'reading': 'energy',
      'cleaning': 'clean', 'trash': 'clean', 'laundry': 'clean', 'dishes': 'clean',
      'table': 'hunger', 'food': 'hunger', 'shopping': 'hunger',
      'pet': 'fun', 'plant': 'fun', 'yard': 'fun', 'errand': 'fun', 'bike': 'fun',
      'music': 'fun', 'art': 'fun', 'game': 'fun', 'outside': 'fun',
    }[key];
