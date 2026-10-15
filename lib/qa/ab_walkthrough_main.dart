import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';
import '../core/models/user.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import 'walkthrough_variants.dart';

/// QA-only web build for A/B testing the first-time walkthrough.
///
/// No Firebase, no sign-in: it shows the real [OnboardingScreen] with a
/// sample family, records how each run went (finished / skipped, where,
/// how long, a clarity rating) in the browser, and summarizes A vs. B.
///
///   flutter run -d chrome -t lib/qa/ab_walkthrough_main.dart
///   flutter build web -t lib/qa/ab_walkthrough_main.dart --base-href /
///
/// URL options: `?variant=A|B` forces a variant, `?role=parent|child`
/// picks the role, `?tester=Name` pre-fills the tester name. Without
/// `variant`, each browser is randomly (50/50) and stickily assigned one.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AbWalkthroughApp());
}

class AbWalkthroughApp extends StatelessWidget {
  const AbWalkthroughApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OnboardingController>(
      // Deliberately not load()-ed: each run uses a fresh user id, and
      // nothing should leak into a real app's saved onboarding progress.
      create: (_) => OnboardingController(),
      child: MaterialApp(
        title: 'Famotive · Walkthrough A/B (QA)',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const AbTestHome(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sample data (stands in for a signed-in household)
// ---------------------------------------------------------------------------

class _SampleFamily {
  static const householdName = 'The Rivera Household';
  static const parent = AppUser(id: 'sample-parent', name: 'Alex Rivera', email: 'alex@example.com', role: UserRole.parent);
  static const child = AppUser(id: 'sample-child', name: 'Maya Rivera', email: '', avatarEmoji: '🦸', role: UserRole.child);
  static const tasks = [
    ('Feed the dog', 10, 5),
    ('Make your bed', 5, 2),
    ('Empty the dishwasher', 15, 8),
  ];
  static const rewards = [('30 min screen time', 20), ('Pick Friday movie', 35)];
}

// ---------------------------------------------------------------------------
// Run results
// ---------------------------------------------------------------------------

enum RunOutcome { finishedTour, finished, skipped, abandoned }

extension on RunOutcome {
  String get label => switch (this) {
        RunOutcome.finishedTour => 'Finished → tour',
        RunOutcome.finished => 'Finished (no tour)',
        RunOutcome.skipped => 'Skipped',
        RunOutcome.abandoned => 'Closed / back',
      };

  bool get completed => this == RunOutcome.finishedTour || this == RunOutcome.finished;
}

class RunResult {
  RunResult({
    required this.tester,
    required this.variant,
    required this.role,
    required this.outcome,
    required this.totalSteps,
    required this.furthestStep,
    required this.exitStep,
    required this.durationMs,
    required this.stepDwellMs,
    required this.startedAt,
    this.clarity,
    this.comment = '',
  });

  final String tester;
  final WalkthroughVariant variant;
  final UserRole role;
  final RunOutcome outcome;
  final int totalSteps;

  /// 1-based.
  final int furthestStep;
  final int exitStep;
  final int durationMs;
  final List<int> stepDwellMs;
  final DateTime startedAt;
  int? clarity;
  String comment;

  Map<String, Object?> toJson() => {
        'tester': tester,
        'variant': variant.code,
        'role': role.name,
        'outcome': outcome.name,
        'totalSteps': totalSteps,
        'furthestStep': furthestStep,
        'exitStep': exitStep,
        'durationMs': durationMs,
        'stepDwellMs': stepDwellMs,
        'startedAt': startedAt.toIso8601String(),
        'clarity': clarity,
        'comment': comment,
      };

  static RunResult fromJson(Map<String, dynamic> j) => RunResult(
        tester: j['tester'] as String? ?? '',
        variant: WalkthroughVariant.parse(j['variant'] as String?) ?? WalkthroughVariant.a,
        role: UserRole.values.byName(j['role'] as String),
        outcome: RunOutcome.values.byName(j['outcome'] as String),
        totalSteps: j['totalSteps'] as int,
        furthestStep: j['furthestStep'] as int,
        exitStep: j['exitStep'] as int,
        durationMs: j['durationMs'] as int,
        stepDwellMs: (j['stepDwellMs'] as List).cast<int>(),
        startedAt: DateTime.parse(j['startedAt'] as String),
        clarity: j['clarity'] as int?,
        comment: j['comment'] as String? ?? '',
      );

  static const csvHeader =
      'startedAt,tester,variant,role,outcome,totalSteps,furthestStep,exitStep,durationSec,clarity,stepDwellSec,comment';

  String toCsvRow() {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final dwell = stepDwellMs.map((ms) => (ms / 1000).toStringAsFixed(1)).join(' | ');
    return [
      startedAt.toIso8601String(),
      q(tester),
      variant.code,
      role.name,
      outcome.name,
      totalSteps,
      furthestStep,
      exitStep,
      (durationMs / 1000).toStringAsFixed(1),
      clarity ?? '',
      q(dwell),
      q(comment),
    ].join(',');
  }
}

/// Saves runs and the sticky variant assignment in browser storage.
class _ResultStore {
  static const _runsKey = 'qa.abWalkthrough.runs';
  static const _variantKey = 'qa.abWalkthrough.variant';

  SharedPreferences? _prefs;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('QA A/B: browser storage unavailable ($e); results won\'t persist');
    }
  }

  List<RunResult> loadRuns() {
    final raw = _prefs?.getString(_runsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => RunResult.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('QA A/B: could not read saved runs ($e)');
      return [];
    }
  }

  Future<void> saveRuns(List<RunResult> runs) async =>
      _prefs?.setString(_runsKey, jsonEncode(runs.map((r) => r.toJson()).toList()));

  WalkthroughVariant assignedVariant() {
    final saved = WalkthroughVariant.parse(_prefs?.getString(_variantKey));
    if (saved != null) return saved;
    final picked = math.Random().nextBool() ? WalkthroughVariant.a : WalkthroughVariant.b;
    _prefs?.setString(_variantKey, picked.code);
    return picked;
  }

  Future<void> setAssignedVariant(WalkthroughVariant v) async => _prefs?.setString(_variantKey, v.code);
}

// ---------------------------------------------------------------------------
// Home: pick a role, start a run, see results
// ---------------------------------------------------------------------------

class AbTestHome extends StatefulWidget {
  const AbTestHome({super.key});

  @override
  State<AbTestHome> createState() => _AbTestHomeState();
}

class _AbTestHomeState extends State<AbTestHome> {
  final _store = _ResultStore();
  final _testerCtrl = TextEditingController();
  bool _ready = false;
  late WalkthroughVariant _variant;
  bool _variantForced = false;
  UserRole _role = UserRole.parent;
  List<RunResult> _runs = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _store.init();
    final params = Uri.base.queryParameters;
    final forced = WalkthroughVariant.parse(params['variant']);
    if (params['role'] == 'child') _role = UserRole.child;
    _testerCtrl.text = params['tester'] ?? '';
    setState(() {
      _variantForced = forced != null;
      _variant = forced ?? _store.assignedVariant();
      _runs = _store.loadRuns();
      _ready = true;
    });
  }

  @override
  void dispose() {
    _testerCtrl.dispose();
    super.dispose();
  }

  Future<void> _startRun() async {
    final controller = context.read<OnboardingController>();
    final guide = _variant.guideFor(_role);
    // A fresh id per run, so every run starts at step 1 with no saved state.
    final userId = 'qa-${DateTime.now().microsecondsSinceEpoch}';
    final total = guide.steps.length;

    final dwell = List<int>.filled(total, 0);
    final started = DateTime.now();
    var current = 0;
    var furthest = 0;
    var stepStart = DateTime.now();

    void onChange() {
      final step = controller.savedStep(userId, guide);
      if (step == current) return;
      final now = DateTime.now();
      dwell[current] += now.difference(stepStart).inMilliseconds;
      stepStart = now;
      current = step;
      furthest = math.max(furthest, step);
    }

    controller.addListener(onChange);
    await OnboardingScreen.open(context, guide: guide, userId: userId, resume: false);
    controller.removeListener(onChange);
    final ended = DateTime.now();
    dwell[current] += ended.difference(stepStart).inMilliseconds;

    final RunOutcome outcome;
    if (controller.consumeTourRequest()) {
      outcome = RunOutcome.finishedTour;
    } else if (controller.isWalkthroughDone(userId)) {
      outcome = controller.wasWalkthroughSkipped(userId) ? RunOutcome.skipped : RunOutcome.finished;
    } else {
      outcome = RunOutcome.abandoned;
    }

    final result = RunResult(
      tester: _testerCtrl.text.trim(),
      variant: _variant,
      role: _role,
      outcome: outcome,
      totalSteps: total,
      furthestStep: furthest + 1,
      exitStep: current + 1,
      durationMs: ended.difference(started).inMilliseconds,
      stepDwellMs: dwell,
      startedAt: started,
    );

    if (!mounted) return;
    // The real app hands off to the spotlight tour / tab shell here; this
    // build stops at the hand-off and asks for feedback instead.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FeedbackDialog(result: result),
    );
    setState(() => _runs = [..._runs, result]);
    await _store.saveRuns(_runs);
  }

  Future<void> _copyCsv() async {
    final csv = [RunResult.csvHeader, ..._runs.map((r) => r.toCsvRow())].join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${_runs.length} run(s) as CSV')),
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all results?'),
        content: const Text('This removes every recorded run from this browser.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _runs = []);
    await _store.saveRuns(_runs);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final theme = Theme.of(context);
    final sampleUser = _role == UserRole.parent ? _SampleFamily.parent : _SampleFamily.child;
    final steps = _variant.guideFor(_role).steps.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Walkthrough A/B Test · QA')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1. Set up the run', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('qa-tester'),
                        controller: _testerCtrl,
                        decoration: const InputDecoration(labelText: 'Tester name (optional)'),
                      ),
                      const SizedBox(height: 16),
                      Text('Role', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      SegmentedButton<UserRole>(
                        segments: const [
                          ButtonSegment(value: UserRole.parent, label: Text('Parent'), icon: Icon(Icons.person)),
                          ButtonSegment(value: UserRole.child, label: Text('Child'), icon: Icon(Icons.child_care)),
                        ],
                        selected: {_role},
                        onSelectionChanged: (s) => setState(() => _role = s.first),
                      ),
                      const SizedBox(height: 16),
                      Text('Variant', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      SegmentedButton<WalkthroughVariant>(
                        segments: [
                          for (final v in WalkthroughVariant.values)
                            ButtonSegment(value: v, label: Text('${v.code} · ${v.label}')),
                        ],
                        selected: {_variant},
                        onSelectionChanged: (s) {
                          setState(() => _variant = s.first);
                          if (!_variantForced) _store.setAssignedVariant(s.first);
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _variantForced
                            ? 'Forced by the ?variant= URL parameter.'
                            : 'Randomly assigned to this browser. For a blind test, don\'t tell the tester which one they got.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      _SampleFamilyCard(user: sampleUser),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const Key('qa-start'),
                          onPressed: _startRun,
                          icon: const Icon(Icons.play_arrow),
                          label: Text('Start walkthrough ($steps steps)'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Summary(runs: _runs),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('3. Runs (${_runs.length})', style: theme.textTheme.titleMedium)),
                          TextButton.icon(
                            onPressed: _runs.isEmpty ? null : _copyCsv,
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Copy CSV'),
                          ),
                          TextButton.icon(
                            onPressed: _runs.isEmpty ? null : _clear,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Clear'),
                          ),
                        ],
                      ),
                      if (_runs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No runs yet.'),
                        ),
                      for (final r in _runs.reversed)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: CircleAvatar(radius: 14, child: Text(r.variant.code)),
                          title: Text('${r.outcome.label} · step ${r.exitStep}/${r.totalSteps} · '
                              '${(r.durationMs / 1000).toStringAsFixed(1)}s'),
                          subtitle: Text([
                            r.role.name,
                            if (r.tester.isNotEmpty) r.tester,
                            if (r.clarity != null) 'clarity ${r.clarity}/5',
                            if (r.comment.isNotEmpty) '"${r.comment}"',
                          ].join(' · ')),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleFamilyCard extends StatelessWidget {
  const _SampleFamilyCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.mutedFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sample data (no login)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text('Signed in as ${user.name} (${user.role.name}) in ${_SampleFamily.householdName}'),
          Text('Tasks: ${_SampleFamily.tasks.map((t) => '${t.$1} (${t.$2} XP, ${t.$3} coins)').join(', ')}',
              style: theme.textTheme.bodySmall),
          Text('Rewards: ${_SampleFamily.rewards.map((r) => '${r.$1} (${r.$2} coins)').join(', ')}',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.runs});

  final List<RunResult> runs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('2. A vs. B summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Variant')),
                  DataColumn(label: Text('Runs'), numeric: true),
                  DataColumn(label: Text('Completed'), numeric: true),
                  DataColumn(label: Text('Skipped'), numeric: true),
                  DataColumn(label: Text('Avg time'), numeric: true),
                  DataColumn(label: Text('Avg clarity'), numeric: true),
                ],
                rows: [
                  for (final v in WalkthroughVariant.values) _row(v, runs.where((r) => r.variant == v).toList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _row(WalkthroughVariant v, List<RunResult> rs) {
    String pct(int n) => rs.isEmpty ? '–' : '${(100 * n / rs.length).round()}%';
    final rated = rs.where((r) => r.clarity != null).toList();
    final avgTime = rs.isEmpty ? '–' : '${(rs.map((r) => r.durationMs).reduce((a, b) => a + b) / rs.length / 1000).toStringAsFixed(1)}s';
    final avgClarity = rated.isEmpty
        ? '–'
        : (rated.map((r) => r.clarity!).reduce((a, b) => a + b) / rated.length).toStringAsFixed(1);
    return DataRow(cells: [
      DataCell(Text('${v.code} · ${v.label}')),
      DataCell(Text('${rs.length}')),
      DataCell(Text(pct(rs.where((r) => r.outcome.completed).length))),
      DataCell(Text(pct(rs.where((r) => r.outcome == RunOutcome.skipped).length))),
      DataCell(Text(avgTime)),
      DataCell(Text(avgClarity)),
    ]);
  }
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({required this.result});

  final RunResult result;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _comment = TextEditingController();
  int? _clarity;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return AlertDialog(
      title: Text(r.outcome.label),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Left at step ${r.exitStep} of ${r.totalSteps} after '
                '${(r.durationMs / 1000).toStringAsFixed(1)}s.'),
            const SizedBox(height: 16),
            const Text('How clear was the walkthrough? (1 = confusing, 5 = very clear)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 1; i <= 5; i++)
                  ChoiceChip(
                    key: Key('qa-clarity-$i'),
                    label: Text('$i'),
                    selected: _clarity == i,
                    onSelected: (_) => setState(() => _clarity = i),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Comment (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('qa-save'),
          onPressed: () {
            r.clarity = _clarity;
            r.comment = _comment.text.trim();
            Navigator.pop(context);
          },
          child: const Text('Save run'),
        ),
      ],
    );
  }
}
