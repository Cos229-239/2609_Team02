import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart';
import '../../../core/models/mini_game.dart';
import '../../../core/models/mini_game_session.dart';
import '../../../core/models/mini_game_settings.dart';
import '../../../core/services/mini_game_service.dart';
import '../../../core/services/xp_multiplier.dart';
import '../../../shared/widgets/app_button.dart';
import '../mini_game_framework.dart';
import '../../../shared/widgets/app_notice.dart';

enum _Phase { intro, playing, result }

/// Common chrome for every mini-game: how-to-play intro → the game → the
/// result with the XP multiplier breakdown, plus safe exits at every step.
///
/// Rewarded mode ([session] set) belongs to one approved task: starting,
/// finishing and skipping go through [MiniGameService], and the bonus shown
/// is a preview until the server confirms it. Casual mode ([session] null)
/// is practice from the Reward Store: nothing is written, no XP.
class MiniGameHostScreen extends StatefulWidget {
  const MiniGameHostScreen({
    super.key,
    required this.gameId,
    this.session,
    this.casualSettings,
    this.casualSeed,
    this.definition,
  });

  /// Rewarded bonus game for an approved task.
  MiniGameHostScreen.rewarded({super.key, required MiniGameSession this.session, this.definition})
    : gameId = session.gameId,
      casualSettings = null,
      casualSeed = null;

  /// The game to host; defaults to the registered one for [gameId].
  final MiniGameDefinition? definition;

  final MiniGameId gameId;
  final MiniGameSession? session;

  /// Settings for casual play (the child's resolved settings).
  final MiniGameSettings? casualSettings;

  /// Seed for casual play (random when null).
  final int? casualSeed;

  bool get isRewarded => session != null;

  @override
  State<MiniGameHostScreen> createState() => _MiniGameHostScreenState();
}

class _MiniGameHostScreenState extends State<MiniGameHostScreen> {
  _Phase _phase = _Phase.intro;
  int _attempt = 0;
  int _seed = 0;
  MiniGameOutcome? _outcome;
  bool _reported = false;

  /// Practice rounds: the difficulty the child picked (remembered on this device).
  DifficultyPreset _practiceLevel = DifficultyPreset.normal;
  static const _practiceLevelKey = 'minigames.practiceDifficulty';

  MiniGameSettings get _settings {
    final session = widget.session;
    if (session != null) return session.settings;
    return (widget.casualSettings ?? const MiniGameSettings()).withPreset(_practiceLevel);
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isRewarded) unawaited(_loadPracticeLevel());
  }

  Future<void> _loadPracticeLevel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_practiceLevelKey);
      final level = DifficultyPreset.values.where((p) => p.name == saved).firstOrNull;
      if (level != null && mounted && _phase != _Phase.playing) setState(() => _practiceLevel = level);
    } catch (e) {
      debugPrint('MiniGameHost: could not load practice difficulty: $e');
    }
  }

  void _setPracticeLevel(DifficultyPreset level) {
    setState(() => _practiceLevel = level);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_practiceLevelKey, level.name))
        .catchError((Object e) {
      debugPrint('MiniGameHost: could not save practice difficulty: $e');
      return false;
    });
  }

  bool _starting = false;

  Future<void> _start() async {
    final session = widget.session;
    if (session != null) {
      if (_starting) return;
      setState(() => _starting = true);
      try {
        _attempt = await context.read<MiniGameService>().start(session);
      } catch (e) {
        if (mounted) {
          setState(() => _starting = false);
          _showError(e);
        }
        return;
      }
      if (!mounted) return;
      _starting = false;
      _seed = session.seedForAttempt(_attempt);
    } else {
      _attempt++;
      _seed = widget.casualSeed ?? math.Random().nextInt(1 << 31);
    }
    setState(() {
      _phase = _Phase.playing;
      _outcome = null;
      _reported = false;
    });
  }

  void _onFinished(MiniGameOutcome outcome) {
    if (_reported || !mounted) return;
    _reported = true;
    final session = widget.session;
    if (session != null) {
      // Queued if offline; the server pays the bonus when it arrives.
      unawaited(context.read<MiniGameService>().finish(session, outcome).catchError((Object e) {
        debugPrint('MiniGameHost: could not report result: $e');
      }));
    }
    setState(() {
      _outcome = outcome;
      _phase = _Phase.result;
    });
  }

  void _showError(Object e) {
    showAppNotice(context, e.toString().replaceFirst('Exception: ', ''), tone: NoticeTone.error);
  }

  Future<void> _skip() async {
    final session = widget.session;
    if (session == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip the bonus?'),
        content: const Text('You keep the XP from your task, but you won\'t get a bonus for it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Skip')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final service = context.read<MiniGameService>();
    unawaited(service.skip(session).catchError((Object e) => debugPrint('MiniGameHost: skip failed: $e')));
    if (mounted) Navigator.of(context).pop();
  }

  /// Leaving mid-game. Rewarded: the session stays started and can be
  /// replayed once; leaving the last allowed attempt skips the bonus.
  Future<bool> _confirmLeave() async {
    final session = widget.session;
    final lastTry = session != null && _attempt >= MiniGameSession.maxAttempts;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the game?'),
        content: Text(
          session == null
              ? 'This practice round won\'t be saved.'
              : lastTry
                  ? 'This was your last try, so the bonus for this task will be skipped. You keep your task XP.'
                  : 'You can come back and try this bonus game one more time from Home.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true) return false;
    if (session != null && lastTry && mounted) {
      final service = context.read<MiniGameService>();
      unawaited(service.skip(session).catchError((Object e) => debugPrint('MiniGameHost: skip failed: $e')));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final playing = _phase == _Phase.playing;
    return PopScope(
      canPop: !playing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !playing) return;
        if (await _confirmLeave() && mounted) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.gameId.emoji} ${widget.gameId.title}'),
          leading: IconButton(
            key: const Key('minigame-close'),
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (!playing || await _confirmLeave()) {
                if (mounted) Navigator.of(this.context).pop();
              }
            },
          ),
        ),
        body: SafeArea(
          child: switch (_phase) {
            _Phase.intro => _Intro(
                gameId: widget.gameId,
                session: widget.session,
                starting: _starting,
                onPlay: _start,
                onSkip: widget.isRewarded ? _skip : null,
                practiceLevel: widget.isRewarded ? null : _practiceLevel,
                onPracticeLevel: _setPracticeLevel,
              ),
            _Phase.playing => _buildGame(),
            _Phase.result => _Result(
                outcome: _outcome!,
                session: widget.session,
                settings: _settings,
                onPlayAgain: widget.isRewarded ? null : _start,
                practiceLevel: widget.isRewarded ? null : _practiceLevel,
                onPracticeLevel: _setPracticeLevel,
              ),
          },
        ),
      ),
    );
  }

  Widget _buildGame() {
    final definition = widget.definition ?? MiniGameRegistry.of(widget.gameId);
    if (definition == null) {
      return const Center(child: Text('This game is coming soon!'));
    }
    return KeyedSubtree(
      key: ValueKey('game-$_attempt-$_seed'),
      child: Builder(
        builder: (context) => definition.build(
          context,
          MiniGamePlayContext(settings: _settings, seed: _seed, onFinished: _onFinished),
        ),
      ),
    );
  }
}

/// Easy / Medium / Hard switch for practice rounds.
class _PracticeLevelPicker extends StatelessWidget {
  const _PracticeLevelPicker({required this.value, required this.onChanged});

  final DifficultyPreset value;
  final ValueChanged<DifficultyPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SegmentedButton<DifficultyPreset>(
        key: const Key('practice-difficulty'),
        showSelectedIcon: false,
        segments: [
          for (final p in DifficultyPreset.values)
            ButtonSegment(
              value: p,
              label: Text('${p.emoji} ${p.childLabel}', key: Key('practice-difficulty-${p.name}')),
            ),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.gameId,
    required this.session,
    required this.onPlay,
    this.onSkip,
    this.starting = false,
    this.practiceLevel,
    this.onPracticeLevel,
  });

  final MiniGameId gameId;
  final MiniGameSession? session;
  final bool starting;
  final VoidCallback onPlay;
  final VoidCallback? onSkip;
  final DifficultyPreset? practiceLevel;
  final ValueChanged<DifficultyPreset>? onPracticeLevel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final maxAward = s == null
        ? null
        : XpMultiplier.award(baseXp: s.baseXp, performance: 1, settings: s.settings.multiplier);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Container(
            width: 120,
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: gameId.color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Text(gameId.emoji, style: const TextStyle(fontSize: 64)),
          ),
        ),
        const SizedBox(height: 16),
        Text(gameId.title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(gameId.howToPlay, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (s == null ? Colors.blueGrey : AppColors.growthGreen).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            s == null
                ? '🎮 Practice round - just for fun. Bonus XP comes from games after an approved task.'
                : '⭐ Bonus round for "${s.taskTitle}"! Play well to turn your ${s.baseXp} XP into up to '
                    '${maxAward!.finalXp} XP (${maxAward.multiplierLabel}).',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (s != null && s.attempts > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Last try - this game was interrupted before.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (practiceLevel != null && onPracticeLevel != null) ...[
          const SizedBox(height: 20),
          Text('How hard?', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _PracticeLevelPicker(value: practiceLevel!, onChanged: onPracticeLevel!),
        ],
        const SizedBox(height: 24),
        AppButton(
          key: const Key('minigame-play'),
          label: 'Play!',
          icon: Icons.play_arrow,
          isLoading: starting,
          onPressed: onPlay,
        ),
        if (onSkip != null) ...[
          const SizedBox(height: 12),
          AppButton(label: 'Skip bonus', variant: AppButtonVariant.secondary, onPressed: onSkip),
        ],
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.outcome,
    required this.session,
    required this.settings,
    this.onPlayAgain,
    this.practiceLevel,
    this.onPracticeLevel,
  });

  final MiniGameOutcome outcome;
  final MiniGameSession? session;
  final MiniGameSettings settings;
  final VoidCallback? onPlayAgain;
  final DifficultyPreset? practiceLevel;
  final ValueChanged<DifficultyPreset>? onPracticeLevel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final preview = XpMultiplier.award(
      baseXp: s?.baseXp ?? 0,
      performance: outcome.performance,
      settings: settings.multiplier,
    );
    final stars = (outcome.performance * 3).round().clamp(0, 3);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(outcome.completed ? '🏆' : '👏', textAlign: TextAlign.center, style: const TextStyle(fontSize: 72)),
        Text(
          outcome.completed ? 'You did it!' : 'Nice try!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '$stars of 3 stars',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 44, color: Colors.amber.shade600),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Score: ${(outcome.performance * 100).round()}%',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        if (s == null)
          Text(
            'Practice round - no XP this time. In a bonus round this score would be worth '
            '${preview.multiplierLabel} XP!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          )
        else
          _RewardBreakdown(session: s, preview: preview),
        if (practiceLevel != null && onPracticeLevel != null) ...[
          const SizedBox(height: 16),
          _PracticeLevelPicker(value: practiceLevel!, onChanged: onPracticeLevel!),
        ],
        const SizedBox(height: 24),
        if (onPlayAgain != null) ...[
          AppButton(label: 'Play again', icon: Icons.replay, onPressed: onPlayAgain),
          const SizedBox(height: 12),
        ],
        AppButton(
          key: const Key('minigame-done'),
          label: 'Done',
          variant: onPlayAgain == null ? AppButtonVariant.success : AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Base XP × multiplier = final XP, then whether the server confirmed it.
class _RewardBreakdown extends StatelessWidget {
  const _RewardBreakdown({required this.session, required this.preview});

  final MiniGameSession session;
  final XpAward preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.read<MiniGameService?>();
    return StreamBuilder<MiniGameSession?>(
      stream: service?.watchSession(session.id),
      builder: (context, snap) {
        final live = snap.data;
        final confirmed = live?.status == MiniGameSessionStatus.rewarded;
        final rejected = live?.status == MiniGameSessionStatus.rejected;
        final award = confirmed && live!.multiplierPct != null
            ? XpAward(baseXp: live.baseXp, multiplierPct: live.multiplierPct!, finalXp: live.finalXp ?? preview.finalXp)
            : preview;
        Widget row(String label, String value, {bool strong = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
                  Text(
                    value,
                    style: (strong ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)
                        ?.copyWith(color: strong ? AppColors.growthGreen : null),
                  ),
                ],
              ),
            );
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.growthGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              row('Task XP', '${award.baseXp} XP'),
              row('Multiplier', award.multiplierLabel),
              row('Bonus', '+${award.bonusXp} XP'),
              const Divider(),
              row('Total for this task', '${award.finalXp} XP', strong: true),
              const SizedBox(height: 8),
              Text(
                confirmed
                    ? 'Bonus added to your XP! ⭐'
                    : rejected
                        ? 'We couldn\'t add this bonus. Your task XP is safe.'
                        : 'Adding your bonus... (it arrives even if you\'re offline right now)',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}
