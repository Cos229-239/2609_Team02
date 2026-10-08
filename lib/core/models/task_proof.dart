import 'package:cloud_firestore/cloud_firestore.dart';

enum ScanVerdict {
  match('Looks like a match', 'The photo looks related to this task.'),

  uncertain('Not sure', "The photo might show this task, but the check isn't sure."),

  noMatch("Doesn't look related", "The photo doesn't look related to this task."),

  unclassified("Couldn't recognize", "The photo couldn't be recognized (too dark, blurry or unusual)."),

  unavailable('Not checked', "This photo wasn't checked automatically.");

  const ScanVerdict(this.label, this.explanation);

  final String label;
  final String explanation;

  bool get needsReview => this != ScanVerdict.match;

  static ScanVerdict fromName(Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return ScanVerdict.unavailable;
  }
}

class ScanLabel {
  const ScanLabel(this.label, this.confidence);

  final String label;
  final double confidence;

  Map<String, dynamic> toMap() => {'label': label, 'confidence': _round(confidence)};

  static ScanLabel? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    final confidence = raw['confidence'];
    if (label is! String || confidence is! num) return null;
    return ScanLabel(label, confidence.toDouble());
  }
}

class KeywordMatch {
  const KeywordMatch({required this.keyword, required this.label, required this.similarity});

  final String keyword;
  final String label;
  final double similarity;

  Map<String, dynamic> toMap() => {'keyword': keyword, 'label': label, 'similarity': _round(similarity)};

  static KeywordMatch? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final keyword = raw['keyword'];
    final label = raw['label'];
    final similarity = raw['similarity'];
    if (keyword is! String || label is! String || similarity is! num) return null;
    return KeywordMatch(keyword: keyword, label: label, similarity: similarity.toDouble());
  }
}

class TaskScanResult {
  const TaskScanResult({
    required this.verdict,
    required this.score,
    this.labels = const [],
    this.matches = const [],
    this.keywords = const [],
    this.flags = const [],
    this.engine,
    this.scannedAt,
  });

  factory TaskScanResult.unavailable({List<String> keywords = const [], DateTime? at}) =>
      TaskScanResult(verdict: ScanVerdict.unavailable, score: 0, keywords: keywords, scannedAt: at);

  final ScanVerdict verdict;
  final double score;
  final List<ScanLabel> labels;
  final List<KeywordMatch> matches;
  final List<String> keywords;
  final List<String> flags;

  bool get isPhotoOfScreen => flags.contains('screen');

  final String? engine;
  final DateTime? scannedAt;

  String get scorePercent => '${(score * 100).round()}%';

  Map<String, dynamic> toMap() => {
        'verdict': verdict.name,
        'score': _round(score),
        'labels': labels.map((l) => l.toMap()).toList(),
        'matches': matches.map((m) => m.toMap()).toList(),
        'keywords': keywords,
        'flags': flags,
        'engine': engine,
        'scannedAt': scannedAt == null ? null : Timestamp.fromDate(scannedAt!),
      };

  static TaskScanResult? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final score = raw['score'];
    return TaskScanResult(
      verdict: ScanVerdict.fromName(raw['verdict']),
      score: score is num ? score.toDouble().clamp(0.0, 1.0) : 0.0,
      labels: [
        for (final l in (raw['labels'] as List? ?? const [])) ?ScanLabel.fromMap(l),
      ],
      matches: [
        for (final m in (raw['matches'] as List? ?? const [])) ?KeywordMatch.fromMap(m),
      ],
      keywords: List<String>.from((raw['keywords'] as List? ?? const []).whereType<String>()),
      flags: List<String>.from((raw['flags'] as List? ?? const []).whereType<String>()),
      engine: raw['engine'] as String?,
      scannedAt: (raw['scannedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class TaskProof {
  const TaskProof({
    this.photoPath,
    this.submittedAt,
    this.deleteAt,
    this.photoDeletedAt,
    this.scan,
    this.parentOverride = false,
  });

  final String? photoPath;
  final DateTime? submittedAt;
  final DateTime? deleteAt;
  final DateTime? photoDeletedAt;
  final TaskScanResult? scan;
  final bool parentOverride;

  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;

  ScanVerdict get verdict => scan?.verdict ?? ScanVerdict.unavailable;

  static TaskProof? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return TaskProof(
      photoPath: raw['photoPath'] as String?,
      submittedAt: (raw['submittedAt'] as Timestamp?)?.toDate(),
      deleteAt: (raw['deleteAt'] as Timestamp?)?.toDate(),
      photoDeletedAt: (raw['photoDeletedAt'] as Timestamp?)?.toDate(),
      scan: TaskScanResult.fromMap(raw['scan']),
      parentOverride: raw['parentOverride'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'photoPath': photoPath,
        'submittedAt': submittedAt == null ? null : Timestamp.fromDate(submittedAt!),
        'deleteAt': deleteAt == null ? null : Timestamp.fromDate(deleteAt!),
        if (photoDeletedAt != null) 'photoDeletedAt': Timestamp.fromDate(photoDeletedAt!),
        'scan': scan?.toMap(),
        'parentOverride': parentOverride,
      };
}

double _round(double v) => (v * 1000).roundToDouble() / 1000;
