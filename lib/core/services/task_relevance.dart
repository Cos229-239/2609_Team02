import 'dart:math' as math;

import '../models/task_proof.dart';

class TaskKeyword {
  const TaskKeyword(this.word, this.weight);

  final String word;
  final double weight;

  @override
  String toString() => '$word($weight)';
}

class TaskRelevance {
  TaskRelevance._();

  // --- Tunables -------------------------------------------------------------

  static const double minLabelConfidence = 0.12;
  static const double embeddingFloor = 0.30;
  static const double embeddingCeiling = 0.65;
  static const double matchThreshold = 0.5;
  static const double uncertainThreshold = 0.25;
  static const double strongRelatedness = 0.85;
  static const double strongLabelConfidence = 0.25;
  static const double supportRelatedness = 0.5;
  static const double supportBonus = 0.35;
  static const int maxPairs = 3;
  static const int maxKeywords = 14;

  static const Set<String> screenWords = {
    'screen', 'screenshot', 'display', 'monitor', 'television', 'tv', 'computer', 'laptop',
    'cellphone', 'phone', 'smartphone', 'tablet', 'ipad', 'iphone', 'electronics',
  };

  static const double screenPenalty = 0.7;
  static const double screenFlagConfidence = 0.3;

  static const Set<String> personWords = {
    'people', 'person', 'adult', 'baby', 'child', 'kid', 'teen', 'toddler', 'man', 'woman', 'boy', 'girl',
    'face', 'portrait', 'selfie', 'crowd', 'human', 'family', 'brother', 'sister',
  };

  static const String screenFlag = 'screen';
  static const double titleWeight = 1.0;
  static const double iconWeight = 0.8;
  static const double descriptionWeight = 0.6;

  // --- Keywords -------------------------------------------------------------

  static const Set<String> _stopWords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'from', 'by',
    'up', 'out', 'off', 'into', 'over', 'under', 'about', 'after', 'before', 'then', 'than', 'when',
    'your', 'you', 'yours', 'my', 'our', 'their', 'his', 'her', 'its', 'it', 'this', 'that', 'these',
    'those', 'all', 'any', 'each', 'every', 'some', 'more', 'most', 'other', 'own', 'same', 'too',
    'very', 'just', 'also', 'only', 'not', 'are', 'was', 'were', 'been', 'being', 'have', 'has', 'had',
    'does', 'did', 'doing', 'will', 'would', 'should', 'could', 'can', 'may', 'might', 'must', 'need',
    'needs', 'let', 'know', 'once', 'done', 'today', 'tonight', 'tomorrow', 'daily', 'weekly', 'minutes',
    'minute', 'hour', 'hours', 'time', 'times', 'amount', 'assigned', 'scheduled', 'needed', 'anything',
    'something', 'everything', 'thing', 'things', 'way', 'away', 'back', 'down', 'around', 'neatly',
    'nice', 'work', 'parent', 'parents', 'ask', 'unclear', 'extra', 'bonus', 'special', 'task', 'tasks',
    'clean', 'cleaning', 'tidy', 'tidying', 'help', 'helping', 'finish', 'finished', 'complete',
    'make', 'making', 'get', 'put', 'take', 'taking', 'go', 'going', 'do', 'keep', 'check', 'double',
    'sure', 'ready', 'share', 'happened', 'enjoy', 'earned', 'wrap', 'first', 'warm', 'run', 'running',
    'straighten', 'fluff', 'tuck', 'load', 'dry', 'sort', 'collect', 'tie', 'refill', 'feed', 'water',
    'set', 'empty', 'wipe', 'pick', 'organize', 'prepare', 'practice', 'spend',
  };

  static const Set<String> _keepAsIs = {
    'clothes', 'glasses', 'pants', 'shorts', 'scissors', 'grass', 'glass', 'dress', 'mess', 'chess',
    'bus', 'plus', 'news', 'series', 'species', 'jeans', 'stairs',
  };

  static const Map<String, List<String>> iconHints = {
    'bed': ['bed', 'bedroom', 'pillow', 'blanket'],
    'cleaning': ['room', 'floor', 'furniture', 'interior room'],
    'trash': ['trash', 'garbage', 'bin', 'bag'],
    'laundry': ['clothes', 'laundry', 'washing machine', 'textile'],
    'dishes': ['dish', 'plate', 'sink', 'kitchen', 'tableware'],
    'table': ['table', 'plate', 'tableware', 'utensil', 'dining'],
    'homework': ['paper', 'notebook', 'document', 'desk', 'pen'],
    'reading': ['book', 'reading', 'page'],
    'pet': ['dog', 'cat', 'pet', 'animal', 'bowl'],
    'plant': ['plant', 'flower', 'pot', 'leaf'],
    'yard': ['lawn', 'grass', 'yard', 'garden', 'outdoor'],
    'outdoors': ['outdoor', 'sky', 'tree', 'park'],
    'outside': ['outdoor', 'sky', 'tree', 'park'],
    'shopping': ['grocery', 'bag', 'store', 'food'],
    'bike': ['bicycle', 'bike', 'outdoor'],
    'music': ['musical instrument', 'piano', 'guitar', 'violin'],
    'art': ['art', 'painting', 'drawing', 'crayon'],
    'food': ['food', 'kitchen', 'meal', 'plate'],
  };

  static List<TaskKeyword> extractKeywords({
    required String title,
    String description = '',
    String? iconKey,
  }) {
    final weights = <String, double>{};
    void add(String word, double weight) {
      final current = weights[word];
      if (current == null || weight > current) weights[word] = weight;
    }

    for (final w in tokenize(title)) {
      add(w, titleWeight);
    }
    for (final w in iconHints[iconKey] ?? const <String>[]) {
      add(w, iconWeight);
    }
    for (final w in tokenize(description)) {
      add(w, descriptionWeight);
    }

    final sorted = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted.take(maxKeywords)) TaskKeyword(e.key, e.value)];
  }

  static List<String> tokenize(String text) {
    final out = <String>[];
    for (final m in RegExp(r"[a-z]+(?:'[a-z]+)?").allMatches(text.toLowerCase())) {
      var w = m.group(0)!.replaceAll(RegExp(r"'.*$"), '');
      if (w.length < 3 || _stopWords.contains(w)) continue;
      w = singular(w);
      if (w.length < 3 || _stopWords.contains(w)) continue;
      if (!out.contains(w)) out.add(w);
    }
    return out;
  }

  static String singular(String w) {
    if (_keepAsIs.contains(w)) return w;
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && RegExp(r'(sh|ch|x|ss|z)es$').hasMatch(w)) return w.substring(0, w.length - 2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us')) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  static String normalizeLabel(String identifier) =>
      identifier.toLowerCase().replaceAll(RegExp(r'[_\-]+'), ' ').trim();

  // --- Similarity -----------------------------------------------------------

  static double lexicalSimilarity(String keyword, String label) {
    final k = singular(keyword.toLowerCase());
    final labelWords = normalizeLabel(label).split(' ').map(singular).toList();
    final keywordWords = k.split(' ');
    if (normalizeLabel(label) == k || labelWords.contains(k)) return 1.0;
    if (keywordWords.length > 1 && keywordWords.every(labelWords.contains)) return 1.0;
    for (final lw in labelWords) {
      for (final kw in keywordWords) {
        if (_isCompoundOf(lw, kw) || _isCompoundOf(kw, lw)) return 0.75;
      }
    }
    return 0;
  }

  static bool _isCompoundOf(String long, String short) =>
      short.length >= 3 && long.length >= short.length + 3 && long.startsWith(short);

  static double relatednessFromCosine(double cosine) {
    final r = (cosine - embeddingFloor) / (embeddingCeiling - embeddingFloor);
    return r.clamp(0.0, 1.0);
  }

  // --- Scoring --------------------------------------------------------------

  static TaskScanResult evaluate({
    required List<TaskKeyword> keywords,
    required List<ScanLabel> labels,
    Map<String, Map<String, double>> cosine = const {},
    double screenLikelihood = 0,
    String? engine,
    DateTime? now,
  }) {
    final usable = labels.where((l) => l.confidence >= minLabelConfidence).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final keywordWords = [for (final k in keywords) k.word];
    final at = now ?? DateTime.now();
    final taskIsAboutScreens = keywordWords.any((k) => screenWords.any((w) => lexicalSimilarity(k, w) > 0));
    var screenConfidence = 0.0;
    if (!taskIsAboutScreens) {
      for (final l in labels.where((l) => l.confidence >= 0.05)) {
        if (normalizeLabel(l.label).split(' ').any(screenWords.contains)) {
          screenConfidence = math.max(screenConfidence, l.confidence);
        }
      }
      screenConfidence = math.max(screenConfidence, screenLikelihood.clamp(0.0, 1.0));
    }
    final flags = [if (screenConfidence >= screenFlagConfidence) screenFlag];
    final taskIsAboutPeople = keywordWords.any((k) => personWords.any((w) => lexicalSimilarity(k, w) > 0));
    bool isPerson(ScanLabel l) => normalizeLabel(l.label).split(' ').any(personWords.contains);
    final evidence = taskIsAboutPeople ? usable : usable.where((l) => !isPerson(l)).toList();

    if (usable.isEmpty) {
      return TaskScanResult(
        verdict: ScanVerdict.unclassified,
        score: 0,
        labels: labels.take(8).toList(),
        keywords: keywordWords,
        // Keep the screen warning: pixel/depth checks can flag a screen even
        // when the labeler returns nothing usable.
        flags: flags,
        engine: engine,
        scannedAt: at,
      );
    }
    if (keywords.isEmpty) {
      return TaskScanResult(
        verdict: ScanVerdict.uncertain,
        score: 0,
        labels: usable.take(8).toList(),
        keywords: const [],
        flags: flags,
        engine: engine,
        scannedAt: at,
      );
    }

    // Best keyword for each label.
    final pairs = <({KeywordMatch match, double value, bool strong})>[];
    for (final label in evidence) {
      ({KeywordMatch match, double value, bool strong})? best;
      for (final k in keywords) {
        final lexical = lexicalSimilarity(k.word, label.label);
        final cos = cosine[k.word]?[label.label];
        final semantic = cos == null ? 0.0 : relatednessFromCosine(cos);
        final related = math.max(lexical, semantic);
        if (related <= 0) continue;
        final value = k.weight * related * math.sqrt(label.confidence);
        if (best == null || value > best.value) {
          best = (
            match: KeywordMatch(keyword: k.word, label: label.label, similarity: related),
            value: value,
            strong: isStrong(keywordWeight: k.weight, relatedness: related, confidence: label.confidence),
          );
        }
      }
      if (best != null) pairs.add(best);
    }
    pairs.sort((a, b) => b.value.compareTo(a.value));
    final top = pairs.take(maxPairs).toList();

    var score = 0.0;
    if (top.isNotEmpty) {
      final base = top.first.value.clamp(0.0, 1.0);
      var miss = 1.0;
      for (final p in top.skip(1)) {
        if (p.match.similarity >= supportRelatedness) miss *= 1 - p.value.clamp(0.0, 1.0);
      }
      score = base + (1 - base) * supportBonus * (1 - miss);
    }
    // No single convincing match: at best "not sure".
    final hasStrong = top.any((p) => p.strong);
    if (!hasStrong) score = math.min(score, matchThreshold - 0.01);
    score *= 1 - screenPenalty * screenConfidence;
    if (flags.contains(screenFlag)) score = math.min(score, matchThreshold - 0.01);
    score = score.clamp(0.0, 1.0);

    final verdict = score >= matchThreshold
        ? ScanVerdict.match
        : score >= uncertainThreshold
            ? ScanVerdict.uncertain
            : ScanVerdict.noMatch;

    return TaskScanResult(
      verdict: verdict,
      score: score,
      labels: usable.take(8).toList(),
      matches: [for (final p in top) p.match],
      keywords: keywordWords,
      flags: flags,
      engine: engine,
      scannedAt: at,
    );
  }

  static bool isStrong({required double keywordWeight, required double relatedness, required double confidence}) =>
      keywordWeight >= iconWeight && relatedness >= strongRelatedness && confidence >= strongLabelConfidence;
}
