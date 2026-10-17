import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/mini_game.dart';
import '../../../core/models/mini_game_settings.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/mini_game_service.dart';
import '../../../core/services/xp_multiplier.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_notice.dart';

/// Parent: bonus-game difficulty and rewards, for the whole family or one
/// child. Every control is bounded to safe values; saving never changes a
/// bonus game that was already offered (sessions keep their snapshot).
class MiniGameSettingsScreen extends StatefulWidget {
  const MiniGameSettingsScreen({super.key, this.initialChildId});

  final String? initialChildId;

  @override
  State<MiniGameSettingsScreen> createState() => _MiniGameSettingsScreenState();
}

class _MiniGameSettingsScreenState extends State<MiniGameSettingsScreen> {
  /// null = household defaults.
  String? _childId;
  late MiniGameSettings _draft;
  bool _useFamily = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _childId = widget.initialChildId;
    _load();
  }

  void _load() {
    final service = context.read<MiniGameService>();
    final child = _childId;
    _useFamily = child == null || !service.hasOverride(child);
    _draft = child == null ? service.householdSettings : service.settingsFor(child);
    _dirty = false;
  }

  void _edit(MiniGameSettings next) => setState(() {
        _draft = next;
        _dirty = true;
      });

  Future<void> _save() async {
    final service = context.read<MiniGameService>();
    final notices = AppNotice.of(context);
    setState(() => _saving = true);
    try {
      final child = _childId;
      if (child == null) {
        await service.saveHouseholdSettings(_draft);
      } else {
        await service.saveChildOverride(child, _useFamily ? null : _draft);
      }
      setState(() => _dirty = false);
      notices.show('Saved. New bonus games use these settings.', tone: NoticeTone.success);
    } catch (e) {
      notices.show(e.toString().replaceFirst('Exception: ', ''), tone: NoticeTone.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    context.watch<MiniGameService>();
    final theme = Theme.of(context);
    final editable = _childId == null || !_useFamily;

    return Scaffold(
      appBar: AppBar(title: const Text('Mini-Game Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Settings for', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Whole family'),
                  selected: _childId == null,
                  onSelected: (_) => setState(() {
                    _childId = null;
                    _load();
                  }),
                ),
                for (final child in db.children)
                  ChoiceChip(
                    avatar: Text(child.avatarEmoji),
                    label: Text(child.name),
                    selected: _childId == child.id,
                    onSelected: (_) => setState(() {
                      _childId = child.id;
                      _load();
                    }),
                  ),
              ],
            ),
            if (_childId != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use the family settings'),
                subtitle: const Text('Turn off to give this child their own difficulty.'),
                value: _useFamily,
                onChanged: (v) => setState(() {
                  _useFamily = v;
                  _dirty = true;
                  if (v) _draft = context.read<MiniGameService>().householdSettings;
                }),
              ),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: !editable,
              child: Opacity(
                opacity: editable ? 1 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bonus games after approved tasks'),
                      subtitle: const Text('A random game can multiply the task\'s XP.'),
                      value: _draft.rewardedGamesEnabled,
                      onChanged: (v) => _edit(_draft.copyWith(rewardedGamesEnabled: v)),
                    ),
                    const SizedBox(height: 8),
                    _BonusSizeCard(settings: _draft.multiplier, onChanged: (m) => _edit(_draft.copyWith(multiplier: m))),
                    const SizedBox(height: 12),
                    for (final id in MiniGameId.values) ...[
                      _GameCard(id: id, settings: _draft, onChanged: _edit),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            AppButton(
              key: const Key('minigame-settings-save'),
              label: 'Save',
              icon: Icons.save_outlined,
              isLoading: _saving,
              onPressed: _dirty ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BonusSizeCard extends StatelessWidget {
  const _BonusSizeCard({required this.settings, required this.onChanged});

  final XpMultiplierSettings settings;
  final ValueChanged<XpMultiplierSettings> onChanged;

  String _x(int pct) => XpAward(baseXp: 0, multiplierPct: pct, finalXp: 0).multiplierLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final example = XpMultiplier.award(baseXp: 20, performance: 1, settings: settings);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⭐ Bonus size', style: theme.textTheme.titleMedium),
          Text(
            'From ${_x(settings.minPct)} for trying to ${_x(settings.maxPct)} for a perfect game. '
            'A perfect game turns a 20 XP task into ${example.finalXp} XP.',
            style: theme.textTheme.bodySmall,
          ),
          RangeSlider(
            values: RangeValues(settings.minPct.toDouble(), settings.maxPct.toDouble()),
            min: XpMultiplierSettings.hardMinPct.toDouble(),
            max: XpMultiplierSettings.hardMaxPct.toDouble(),
            divisions: 8,
            labels: RangeLabels(_x(settings.minPct), _x(settings.maxPct)),
            onChanged: (v) {
              final min = v.start.round().clamp(100, 150);
              final max = v.end.round().clamp(min, XpMultiplierSettings.hardMaxPct);
              onChanged(XpMultiplierSettings(minPct: min, maxPct: max, curve: settings.curve));
            },
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final (curve, label) in const [
                (MultiplierCurve.gentle, 'Easy to earn'),
                (MultiplierCurve.balanced, 'Balanced'),
                (MultiplierCurve.challenging, 'For great play'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: settings.curve == curve,
                  onSelected: (_) =>
                      onChanged(XpMultiplierSettings(minPct: settings.minPct, maxPct: settings.maxPct, curve: curve)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.id, required this.settings, required this.onChanged});

  final MiniGameId id;
  final MiniGameSettings settings;
  final ValueChanged<MiniGameSettings> onChanged;

  static const _often = [(0, 'Never'), (1, 'Normal'), (3, 'Often'), (5, 'Most')];

  MiniGameSettings _preset(DifficultyPreset p) => switch (id) {
        MiniGameId.balloonPopper => settings.copyWith(balloonPopper: BalloonPopperSettings.preset(p)),
        MiniGameId.matchPairs => settings.copyWith(matchPairs: MatchPairsSettings.preset(p)),
        MiniGameId.jumpAndRun => settings.copyWith(jumpAndRun: JumpAndRunSettings.preset(p)),
        MiniGameId.memoryRun => settings.copyWith(memoryRun: MemoryRunSettings.preset(p)),
      };

  DifficultyPreset? get _currentPreset {
    for (final p in DifficultyPreset.values) {
      if (_mapEquals(_preset(p).gameSettings(id), settings.gameSettings(id))) return p;
    }
    return null;
  }

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a.length == b.length && a.keys.every((k) => a[k] == b[k]);

  Widget _slider(BuildContext context, String label, int value, IntRange range, String Function(int) show,
      MiniGameSettings Function(int) apply) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${show(value)}', style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: value.toDouble(),
          min: range.min.toDouble(),
          max: range.max.toDouble(),
          divisions: range.max - range.min,
          label: show(value),
          onChanged: (v) => onChanged(apply(v.round())),
        ),
      ],
    );
  }

  List<Widget> _details(BuildContext context) {
    String speed(int s) => const {1: 'Slow', 2: 'Normal', 3: 'Fast'}[s] ?? '$s';
    String amount(int s) => const {1: 'A few', 2: 'Some', 3: 'Lots'}[s] ?? '$s';
    switch (id) {
      case MiniGameId.balloonPopper:
        final b = settings.balloonPopper;
        return [
          _slider(context, 'Balloons to pop', b.targetCount, BalloonPopperSettings.targetRange, (v) => '$v',
              (v) => settings.copyWith(balloonPopper: BalloonPopperSettings(targetCount: v, timeLimitSec: b.timeLimitSec))),
          _slider(context, 'Time', b.timeLimitSec, BalloonPopperSettings.timeRange, (v) => '$v seconds',
              (v) => settings.copyWith(balloonPopper: BalloonPopperSettings(targetCount: b.targetCount, timeLimitSec: v))),
        ];
      case MiniGameId.matchPairs:
        final m = settings.matchPairs;
        return [
          _slider(context, 'Pairs of cards', m.pairs, MatchPairsSettings.pairsRange, (v) => '$v',
              (v) => settings.copyWith(matchPairs: MatchPairsSettings(pairs: v, maxMisses: m.maxMisses))),
          _slider(context, 'Misses allowed', m.maxMisses, MatchPairsSettings.missesRange, (v) => '$v',
              (v) => settings.copyWith(matchPairs: MatchPairsSettings(pairs: m.pairs, maxMisses: v))),
        ];
      case MiniGameId.jumpAndRun:
        final j = settings.jumpAndRun;
        JumpAndRunSettings with3({int? d, int? o, int? c}) => JumpAndRunSettings(
            durationSec: d ?? j.durationSec, obstacleDensity: o ?? j.obstacleDensity, collectibleFrequency: c ?? j.collectibleFrequency);
        return [
          _slider(context, 'Run length', j.durationSec, JumpAndRunSettings.durationRange, (v) => '$v seconds',
              (v) => settings.copyWith(jumpAndRun: with3(d: v))),
          _slider(context, 'Obstacles', j.obstacleDensity, JumpAndRunSettings.densityRange, amount,
              (v) => settings.copyWith(jumpAndRun: with3(o: v))),
          _slider(context, 'Stars', j.collectibleFrequency, JumpAndRunSettings.collectibleRange, amount,
              (v) => settings.copyWith(jumpAndRun: with3(c: v))),
        ];
      case MiniGameId.memoryRun:
        final r = settings.memoryRun;
        return [
          _slider(context, 'Steps for the top prize', r.targetLength, MemoryRunSettings.lengthRange, (v) => '$v',
              (v) => settings.copyWith(memoryRun: MemoryRunSettings(targetLength: v, speed: r.speed))),
          _slider(context, 'Pattern speed', r.speed, MemoryRunSettings.speedRange, speed,
              (v) => settings.copyWith(memoryRun: MemoryRunSettings(targetLength: r.targetLength, speed: v))),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _currentPreset;
    final weight = settings.weightOf(id);
    return AppCard(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          leading: Text(id.emoji, style: const TextStyle(fontSize: 28)),
          title: Text(id.title, style: theme.textTheme.titleMedium),
          subtitle: Text(
            weight == 0 ? 'Not picked as a bonus game' : (preset == null ? 'Custom' : _presetLabel(preset)),
            style: theme.textTheme.bodySmall,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<DifficultyPreset?>(
                emptySelectionAllowed: true,
                segments: [
                  for (final p in DifficultyPreset.values) ButtonSegment(value: p, label: Text(_presetLabel(p))),
                ],
                selected: {preset},
                onSelectionChanged: (s) {
                  final p = s.firstOrNull;
                  if (p != null) onChanged(_preset(p));
                },
              ),
            ),
            const SizedBox(height: 8),
            ..._details(context),
            Align(alignment: Alignment.centerLeft, child: Text('How often it\'s picked', style: theme.textTheme.bodyMedium)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final (w, label) in _often)
                  ChoiceChip(
                    label: Text(label),
                    selected: weight == w,
                    selectedColor: AppColors.growthGreen.withValues(alpha: 0.2),
                    onSelected: (_) => onChanged(settings.copyWith(weights: {...settings.weights, id: w})),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _presetLabel(DifficultyPreset p) => switch (p) {
        DifficultyPreset.easy => 'Easy',
        DifficultyPreset.normal => 'Normal',
        DifficultyPreset.hard => 'Hard',
      };
}
