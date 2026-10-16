import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/models/task.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/database_service.dart';
import '../tasks/task_completion_flow.dart';

/// Rex's Room: the child's 3D voxel pet game (games/rex, bundled into
/// assets/rex/index.html), hosted in a full-screen WebView.
///
/// The child's real tasks are pushed in with `RexGame.setTasks` whenever the
/// database changes. When the child taps "Done!" in the game it posts
/// `taskCompleted`, and we run the normal [startTaskCompletion] flow (photo
/// proof included), so approvals still go through a parent. Rex's needs,
/// in-game coins and items are saved in the WebView, one slot per child.
class RexRoomScreen extends StatefulWidget {
  const RexRoomScreen({super.key});

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
  String? _childId;
  bool _ready = false;
  String? _lastTasksJson;

  @override
  void initState() {
    super.initState();
    _db = context.read<DatabaseService>();
    _childId = context.read<AuthService>().currentUser?.id;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(RexRoomScreen._background)
      ..addJavaScriptChannel('FamotiveBridge', onMessageReceived: _onMessage);
    _db.addListener(_pushTasks);
    _load();
  }

  @override
  void dispose() {
    _db.removeListener(_pushTasks);
    super.dispose();
  }

  Future<void> _load() async {
    final html = await rootBundle.loadString(RexRoomScreen._asset);
    final config = jsonEncode({'player': _childId ?? ''});
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
          'care': ?_careFor(t.icon),
        },
    ]);
    if (json == _lastTasksJson) return;
    _lastTasksJson = json;
    _controller.runJavaScript('window.RexGame && RexGame.setTasks($json);');
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
        _pushTasks();
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
      case 'close':
        if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RexRoomScreen._background,
      body: WebViewWidget(controller: _controller),
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
