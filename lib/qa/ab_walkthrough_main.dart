import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app.dart';
import '../app/theme.dart';
import '../core/models/user.dart';
import '../core/services/demo_mode.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import 'demo_family.dart';
import 'walkthrough_variants.dart';

/// QA-only web build for A/B testing the first-time walkthrough.
///
/// No Firebase, no sign-in. Each run:
///   1. shows the real [OnboardingScreen] for a random variant (A/B) and
///      role (parent/child), timing every step;
///   2. opens the whole app as that role on sample data (the Rivera
///      Household, see demo_family.dart), all in memory;
///   3. "End test" (in Settings, where "Log Out" normally is) closes the
///      app and asks the tester to fill in the external survey
///      ([kSurveyUrl]).
///
/// A "VERSION A" / "VERSION B" watermark is shown over the screen during a
/// run so screenshots and recordings say which walkthrough was tested.
///
///   flutter run -d chrome -t lib/qa/ab_walkthrough_main.dart
///
/// URL options: `?variant=A|B` forces a variant, `?role=parent|child`
/// forces the role, `?tester=Name` is passed to the survey, `?survey=<url>`
/// overrides [kSurveyUrl], and `?setup=1` shows the manual setup + results
/// screen instead of starting right away.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AbWalkthroughApp());
}

/// The survey testers fill in after "End test", opened in a new tab.
///
/// These placeholders are replaced (URL-encoded) before opening it:
/// `{version}` (A or B), `{role}` (parent or child), `{tester}` (the
/// `?tester=` name, if any) and `{run}` (the run code shown to the tester
/// and saved with the run, to match survey answers to timings).
///
/// The Tally form "Famotive Walkthrough A/B Test". Tally ignores URL
/// parameters it has no field for; to record these with each answer, add
/// Hidden fields named `version`, `role`, `run` and `tester` to the form
/// (Tally editor → type /hidden). The form's own "Which walkthrough version
/// did you test?" question is answered by the tester from the watermark.
const kSurveyUrl = 'https://tally.so/r/LD1bez?version={version}&role={role}&run={run}&tester={tester}';

class AbWalkthroughApp extends StatefulWidget {
  const AbWalkthroughApp({super.key, this.queryParameters, this.random});

  /// Overrides the page's URL query parameters (for tests).
  final Map<String, String>? queryParameters;

  /// Overrides the random source for variant/role picks (for tests).
  final math.Random? random;

  @override
  State<AbWalkthroughApp> createState() => _AbWalkthroughAppState();
}

class _AbWalkthroughAppState extends State<AbWalkthroughApp> {
  /// Variant of the run in progress (shown as the watermark), else null.
  final _watermark = ValueNotifier<WalkthroughVariant?>(null);

  @override
  void dispose() {
    _watermark.dispose();
    super.dispose();
  }

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
        // Drawn above every route, including the demo app.
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child!,
            _VersionWatermark(variant: _watermark),
          ],
        ),
        home: AbTestHome(
          queryParameters: widget.queryParameters,
          random: widget.random,
          watermark: _watermark,
        ),
      ),
    );
  }
}

/// Large, faint, diagonal "VERSION A/B" over the whole screen. Ignores
/// touches so it never gets in the way.
class _VersionWatermark extends StatelessWidget {
  const _VersionWatermark({required this.variant});

  final ValueNotifier<WalkthroughVariant?> variant;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WalkthroughVariant?>(
      valueListenable: variant,
      builder: (context, v, _) {
        if (v == null) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.85,
                child: Transform.rotate(
                  angle: -math.pi / 8,
                  child: FittedBox(
                    child: Text(
                      'VERSION ${v.code}',
                      key: const Key('qa-watermark'),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 96,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        decoration: TextDecoration.none,
                        color: Colors.grey.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
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
    required this.runId,
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
    this.appDurationMs = 0,
  });

  /// Short code shown to the tester and sent to the survey ({run}).
  final String runId;
  final String tester;
  final WalkthroughVariant variant;
  final UserRole role;
  final RunOutcome outcome;
  final int totalSteps;

  /// 1-based.
  final int furthestStep;
  final int exitStep;

  /// Time in the walkthrough.
  final int durationMs;
  final List<int> stepDwellMs;
  final DateTime startedAt;

  /// Time spent in the demo app afterwards, until "End test".
  int appDurationMs;

  Map<String, Object?> toJson() => {
        'runId': runId,
        'tester': tester,
        'variant': variant.code,
        'role': role.name,
        'outcome': outcome.name,
        'totalSteps': totalSteps,
        'furthestStep': furthestStep,
        'exitStep': exitStep,
        'durationMs': durationMs,
        'appDurationMs': appDurationMs,
        'stepDwellMs': stepDwellMs,
        'startedAt': startedAt.toIso8601String(),
      };

  static RunResult fromJson(Map<String, dynamic> j) => RunResult(
        runId: j['runId'] as String? ?? '',
        tester: j['tester'] as String? ?? '',
        variant: WalkthroughVariant.parse(j['variant'] as String?) ?? WalkthroughVariant.a,
        role: UserRole.values.byName(j['role'] as String),
        outcome: RunOutcome.values.byName(j['outcome'] as String),
        totalSteps: j['totalSteps'] as int,
        furthestStep: j['furthestStep'] as int,
        exitStep: j['exitStep'] as int,
        durationMs: j['durationMs'] as int,
        appDurationMs: j['appDurationMs'] as int? ?? 0,
        stepDwellMs: (j['stepDwellMs'] as List).cast<int>(),
        startedAt: DateTime.parse(j['startedAt'] as String),
      );

  static const csvHeader =
      'startedAt,runId,tester,variant,role,outcome,totalSteps,furthestStep,exitStep,walkthroughSec,appSec,stepDwellSec';

  String toCsvRow() {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    String sec(int ms) => (ms / 1000).toStringAsFixed(1);
    return [
      startedAt.toIso8601String(),
      runId,
      q(tester),
      variant.code,
      role.name,
      outcome.name,
      totalSteps,
      furthestStep,
      exitStep,
      sec(durationMs),
      sec(appDurationMs),
      q(stepDwellMs.map(sec).join(' | ')),
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
// Home: runs the test, then the thank-you / survey card (or, with
// ?setup=1, the manual setup + results screen)
// ---------------------------------------------------------------------------

class AbTestHome extends StatefulWidget {
  const AbTestHome({super.key, this.queryParameters, this.random, this.watermark});

  final Map<String, String>? queryParameters;
  final math.Random? random;

  /// Set to the running variant for the "VERSION A/B" watermark.
  final ValueNotifier<WalkthroughVariant?>? watermark;

  @override
  State<AbTestHome> createState() => _AbTestHomeState();
}

class _AbTestHomeState extends State<AbTestHome> {
  final _store = _ResultStore();
  final _testerCtrl = TextEditingController();
  late final math.Random _random = widget.random ?? math.Random();
  bool _ready = false;
  late WalkthroughVariant _variant;
  bool _variantForced = false;
  WalkthroughVariant? _forcedVariant;
  UserRole? _forcedRole;
  UserRole _role = UserRole.parent;
  List<RunResult> _runs = [];
  String _surveyTemplate = kSurveyUrl;

  /// Manual setup + results screen (`?setup=1`). Off by default: the page
  /// goes straight into a randomized run.
  bool _setupMode = false;
  bool _running = false;

  /// The last run finished in this page visit (for the survey link).
  RunResult? _lastRun;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _store.init();
    final params = widget.queryParameters ?? Uri.base.queryParameters;
    _forcedVariant = WalkthroughVariant.parse(params['variant']);
    _forcedRole = switch (params['role']?.toLowerCase()) {
      'parent' => UserRole.parent,
      'child' => UserRole.child,
      _ => null,
    };
    final survey = params['survey'];
    if (survey != null && survey.isNotEmpty) _surveyTemplate = survey;
    final setup = params['setup']?.toLowerCase();
    _testerCtrl.text = params['tester'] ?? '';
    setState(() {
      _setupMode = setup != null && setup != '0' && setup != 'false';
      _role = _forcedRole ?? UserRole.parent;
      _variantForced = _forcedVariant != null;
      // In randomized mode the real pick happens per run in _startRandomRun.
      _variant = _forcedVariant ?? (_setupMode ? _store.assignedVariant() : WalkthroughVariant.a);
      _runs = _store.loadRuns();
      _ready = true;
    });
    if (!_setupMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRandomRun();
      });
    }
  }

  @override
  void dispose() {
    _testerCtrl.dispose();
    super.dispose();
  }

  WalkthroughVariant _pickVariant() =>
      _forcedVariant ?? (_random.nextBool() ? WalkthroughVariant.a : WalkthroughVariant.b);

  UserRole _pickRole() => _forcedRole ?? (_random.nextBool() ? UserRole.parent : UserRole.child);

  /// Starts a run with a freshly randomized variant and role (unless forced
  /// by the URL).
  Future<void> _startRandomRun() async {
    if (_running) return;
    setState(() {
      _variant = _pickVariant();
      _role = _pickRole();
    });
    await _startRun();
  }

  Future<void> _startRun() async {
    if (_running) return;
    final watermark = widget.watermark;
    setState(() => _running = true);
    watermark?.value = _variant;
    try {
      await _runTest();
    } finally {
      watermark?.value = null;
      if (mounted) setState(() => _running = false);
    }
  }

  /// Walkthrough, then the demo app until "End test", then save the run.
  Future<void> _runTest() async {
    final controller = context.read<OnboardingController>();
    final variant = _variant;
    final role = _role;
    final guide = variant.guideFor(role);
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
      runId: _runCode(started),
      tester: _testerCtrl.text.trim(),
      variant: variant,
      role: role,
      outcome: outcome,
      totalSteps: total,
      furthestStep: furthest + 1,
      exitStep: current + 1,
      durationMs: ended.difference(started).inMilliseconds,
      stepDwellMs: dwell,
      startedAt: started,
    );

    if (!mounted) return;
    // Like the real app, hand off to the tabs (and the spotlight tour if
    // they asked for it), here on sample data.
    result.appDurationMs = await _openDemoApp(role, tour: outcome == RunOutcome.finishedTour);

    if (!mounted) return;
    setState(() {
      _runs = [..._runs, result];
      _lastRun = result;
    });
    await _store.saveRuns(_runs);
  }

  /// Runs the full app as [role] on fresh sample data until "End test" (or
  /// the browser's back button). Returns how long it was open.
  Future<int> _openDemoApp(UserRole role, {required bool tour}) async {
    final session = await DemoSession.start(role);
    if (!mounted) return 0;

    // Fresh and never load()-ed, so the app doesn't start the walkthrough
    // again (it was just shown) and nothing is saved between runs.
    final onboarding = OnboardingController();
    if (tour) {
      // The tab shell picks this up once it's on screen.
      Future.delayed(const Duration(milliseconds: 1200), onboarding.requestTour);
    }

    final opened = DateTime.now();
    await Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (routeContext, _, _) => FamotiveApp(
        authService: session.authService,
        navigatorKey: GlobalKey<NavigatorState>(),
        onboardingController: onboarding,
        firestore: session.firestore,
        demoMode: DemoMode(onEndTest: () => Navigator.of(routeContext).pop()),
      ),
    ));
    return DateTime.now().difference(opened).inMilliseconds;
  }

  /// e.g. "K3F9QZ": short enough to type into a survey.
  static String _runCode(DateTime t) =>
      (t.millisecondsSinceEpoch % 2176782336).toRadixString(36).toUpperCase().padLeft(6, '0');

  Uri? _surveyUri(RunResult run) {
    if (_surveyTemplate.trim().isEmpty) return null;
    String enc(String s) => Uri.encodeQueryComponent(s);
    final url = _surveyTemplate
        .replaceAll('{version}', enc(run.variant.code))
        .replaceAll('{role}', enc(run.role.name))
        .replaceAll('{tester}', enc(run.tester))
        .replaceAll('{run}', enc(run.runId));
    return Uri.tryParse(url);
  }

  Future<void> _openSurvey(RunResult run) async {
    final uri = _surveyUri(run);
    if (uri == null) return;
    final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open the survey: $uri")),
      );
    }
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
    if (!_setupMode) return _buildRandomized(context);
    final theme = Theme.of(context);
    final sampleUser = _role == UserRole.parent ? DemoFamily.parent : DemoFamily.maya;
    final steps = _variant.guideFor(_role).steps.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Walkthrough A/B Test · QA')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_lastRun != null) ...[
                _SurveyCard(
                  run: _lastRun!,
                  surveyReady: _surveyUri(_lastRun!) != null,
                  onSurvey: () => _openSurvey(_lastRun!),
                ),
                const SizedBox(height: 12),
              ],
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
                        _variantForced ? 'Forced by the ?variant= URL parameter.' : 'Pick the variant to test.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      _SampleFamilyCard(user: sampleUser),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const Key('qa-start'),
                          onPressed: _running ? null : _startRun,
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
                            'app ${(r.appDurationMs / 1000).toStringAsFixed(0)}s',
                            if (r.runId.isNotEmpty) 'run ${r.runId}',
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

  /// What sits behind the test in the default (randomized) mode: a
  /// "starting" placeholder before the first run, then the survey card
  /// with a button for another random run.
  Widget _buildRandomized(BuildContext context) {
    final last = _lastRun;
    return Scaffold(
      appBar: AppBar(title: const Text('Famotive Test · QA')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: last == null
                // Static text, not a spinner: this stays mounted behind the test.
                ? const Center(child: Text('Starting the test…'))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SurveyCard(
                        run: last,
                        surveyReady: _surveyUri(last) != null,
                        onSurvey: () => _openSurvey(last),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('qa-again'),
                          onPressed: _running ? null : _startRandomRun,
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Test again (new random version)'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('qa-show-results'),
                        onPressed: () => setState(() => _setupMode = true),
                        child: const Text('Setup & results'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// After "End test": thanks, the run's version + code, and the survey button.
class _SurveyCard extends StatelessWidget {
  const _SurveyCard({required this.run, required this.surveyReady, required this.onSurvey});

  final RunResult run;
  final bool surveyReady;
  final VoidCallback onSurvey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text('Thanks! One last step.', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'You tested VERSION ${run.variant.code} as a ${run.role.name}. '
              'Please tell us how it went in the short survey.',
              key: const Key('qa-survey-text'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            SelectableText('Run code: ${run.runId}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('qa-survey'),
                onPressed: surveyReady ? onSurvey : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Take the survey'),
              ),
            ),
            if (!surveyReady) ...[
              const SizedBox(height: 6),
              Text('Survey link not set up yet (kSurveyUrl in lib/qa/ab_walkthrough_main.dart).',
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ],
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
          Text('Sample data (no login, nothing is saved)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text('Signed in as ${user.name} (${user.role.name}) in ${DemoFamily.householdName}'),
          Text(
            'Kids: ${DemoFamily.maya.name}, ${DemoFamily.leo.name}. Tasks in every state, '
            'repeating chores and the starter rewards.',
            style: theme.textTheme.bodySmall,
          ),
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
            const SizedBox(height: 4),
            Text('Ratings and comments are in the survey; match them with the run code.',
                style: theme.textTheme.bodySmall),
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
                  DataColumn(label: Text('Avg walkthrough'), numeric: true),
                  DataColumn(label: Text('Avg in app'), numeric: true),
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
    String avg(int Function(RunResult) ms) =>
        rs.isEmpty ? '–' : '${(rs.map(ms).reduce((a, b) => a + b) / rs.length / 1000).toStringAsFixed(1)}s';
    return DataRow(cells: [
      DataCell(Text('${v.code} · ${v.label}')),
      DataCell(Text('${rs.length}')),
      DataCell(Text(pct(rs.where((r) => r.outcome.completed).length))),
      DataCell(Text(pct(rs.where((r) => r.outcome == RunOutcome.skipped).length))),
      DataCell(Text(avg((r) => r.durationMs))),
      DataCell(Text(avg((r) => r.appDurationMs))),
    ]);
  }
}
