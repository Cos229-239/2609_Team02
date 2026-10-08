import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task_proof.dart';
import 'package:famotive/core/services/task_relevance.dart';

List<String> words(List<TaskKeyword> keywords) => [for (final k in keywords) k.word];

void main() {
  group('TaskRelevance.extractKeywords', () {
    test('keeps content words, drops stop words and chore verbs', () {
      final k = TaskRelevance.extractKeywords(title: 'Clean your bedroom');
      expect(words(k), ['bedroom']);
      expect(k.single.weight, TaskRelevance.titleWeight);
    });

    test('singularizes and adds icon hints with lower weight', () {
      final k = TaskRelevance.extractKeywords(title: 'Wash the Dishes', iconKey: 'dishes');
      expect(words(k), contains('dish'));
      expect(words(k), contains('sink'));
      final dish = k.firstWhere((x) => x.word == 'dish');
      final sink = k.firstWhere((x) => x.word == 'sink');
      expect(dish.weight, greaterThan(sink.weight));
    });

    test('a word in both title and description keeps the title weight', () {
      final k = TaskRelevance.extractKeywords(title: 'Feed the dog', description: 'Fill the dog bowl with food');
      expect(k.firstWhere((x) => x.word == 'dog').weight, TaskRelevance.titleWeight);
      expect(k.firstWhere((x) => x.word == 'bowl').weight, TaskRelevance.descriptionWeight);
    });

    test('singular handles common plurals', () {
      expect(TaskRelevance.singular('toys'), 'toy');
      expect(TaskRelevance.singular('berries'), 'berry');
      expect(TaskRelevance.singular('boxes'), 'box');
      expect(TaskRelevance.singular('clothes'), 'clothes');
      expect(TaskRelevance.singular('glass'), 'glass');
    });
  });

  group('TaskRelevance.lexicalSimilarity', () {
    test('exact, stem and unrelated', () {
      expect(TaskRelevance.lexicalSimilarity('bed', 'bed'), 1.0);
      expect(TaskRelevance.lexicalSimilarity('bedroom', 'bed'), 0.75);
      expect(TaskRelevance.lexicalSimilarity('dish', 'dishwasher'), 0.75);
      // Near misses that aren't compounds don't count.
      expect(TaskRelevance.lexicalSimilarity('corner', 'cord'), 0);
      expect(TaskRelevance.lexicalSimilarity('pillow', 'pill'), 0);
      expect(TaskRelevance.lexicalSimilarity('room', 'interior room'), 1.0);
      expect(TaskRelevance.lexicalSimilarity('dog', 'laptop'), 0);
    });
  });

  group('TaskRelevance.evaluate', () {
    final bedroom = TaskRelevance.extractKeywords(title: 'Clean your bedroom', iconKey: 'cleaning');

    test('the spec example: bedroom labels are a match', () {
      final result = TaskRelevance.evaluate(
        keywords: bedroom,
        labels: const [
          ScanLabel('bed', 0.82),
          ScanLabel('furniture', 0.74),
          ScanLabel('interior room', 0.61),
          ScanLabel('structure', 0.40),
        ],
      );
      expect(result.verdict, ScanVerdict.match);
      expect(result.score, greaterThan(TaskRelevance.matchThreshold));
      expect(result.matches.map((m) => m.label), contains('bed'));
    });

    test('unrelated labels are not a match', () {
      final result = TaskRelevance.evaluate(
        keywords: bedroom,
        labels: const [ScanLabel('coffee mug', 0.9), ScanLabel('laptop', 0.7)],
        cosine: const {
          'bedroom': {'coffee mug': 0.02, 'laptop': 0.05},
        },
      );
      expect(result.verdict, ScanVerdict.noMatch);
      expect(result.score, lessThan(TaskRelevance.uncertainThreshold));
      expect(result.isPhotoOfScreen, isTrue);
    });

    test('embedding similarity counts when words differ', () {
      final keywords = TaskRelevance.extractKeywords(title: 'Walk the puppy');
      final result = TaskRelevance.evaluate(
        keywords: keywords,
        labels: const [ScanLabel('dog', 0.9)],
        cosine: const {
          'walk': {'dog': 0.15},
          'puppy': {'dog': 0.62},
        },
      );
      expect(result.verdict, ScanVerdict.match);
      expect(result.matches.first.keyword, 'puppy');
    });

    test('a weak relation is uncertain, not proof', () {
      final keywords = TaskRelevance.extractKeywords(title: 'Water the garden');
      final result = TaskRelevance.evaluate(
        keywords: keywords,
        labels: const [ScanLabel('flower', 0.3)],
        cosine: const {
          'garden': {'flower': 0.50},
        },
      );
      expect(result.verdict, ScanVerdict.uncertain);
    });

    test('many loosely related labels are not a match', () {
      final makeBed = TaskRelevance.extractKeywords(
        title: 'Make the bed',
        description: 'Make the bed neatly - straighten the sheets, fluff the pillows and tuck in the corners.',
        iconKey: 'bed',
      );
      final result = TaskRelevance.evaluate(
        keywords: makeBed,
        labels: const [ScanLabel('clothing', 0.8), ScanLabel('textile', 0.6), ScanLabel('fleece', 0.4)],
        cosine: const {
          'blanket': {'clothing': 0.45, 'fleece': 0.50},
          'pillow': {'textile': 0.55},
          'sheet': {'textile': 0.58},
        },
      );
      expect(result.verdict, isNot(ScanVerdict.match));
      expect(result.score, lessThan(TaskRelevance.matchThreshold));
    });

    test('people in the photo are not evidence for a chore', () {
      final result = TaskRelevance.evaluate(
        keywords: TaskRelevance.extractKeywords(
          title: 'Make the bed',
          description: 'Make the bed neatly - straighten the sheets, fluff the pillows and tuck in the corners.',
          iconKey: 'bed',
        ),
        labels: const [
          ScanLabel('people', 0.77),
          ScanLabel('adult', 0.77),
          ScanLabel('baby', 0.26),
          ScanLabel('toy', 0.08),
          ScanLabel('consumer electronics', 0.08),
        ],
        // Embedding drift that produced the old 91%.
        cosine: const {
          'blanket': {'baby': 0.48, 'people': 0.31},
          'bed': {'baby': 0.42, 'adult': 0.33},
          'pillow': {'baby': 0.45},
        },
      );
      expect(result.verdict, ScanVerdict.noMatch);
      expect(result.matches, isEmpty);
    });

    test('people count when the task is about a person', () {
      final result = TaskRelevance.evaluate(
        keywords: TaskRelevance.extractKeywords(title: 'Read to the baby'),
        labels: const [ScanLabel('baby', 0.8)],
      );
      expect(result.verdict, ScanVerdict.match);
    });

    test('a photo of a screen is never a match, even if the thing is on it', () {
      final result = TaskRelevance.evaluate(
        keywords: TaskRelevance.extractKeywords(title: 'Make the bed', iconKey: 'bed'),
        labels: const [ScanLabel('screen', 0.7), ScanLabel('bed', 0.6)],
      );
      expect(result.isPhotoOfScreen, isTrue);
      expect(result.verdict, isNot(ScanVerdict.match));
    });

    test('the device screen check catches a recaptured photo', () {
      final keywords = TaskRelevance.extractKeywords(title: 'Make the bed', iconKey: 'bed');
      const labels = [
        ScanLabel('structure', 0.90),
        ScanLabel('wood processed', 0.88),
        ScanLabel('bedding', 0.74),
        ScanLabel('furniture', 0.60),
        ScanLabel('bed', 0.60),
        ScanLabel('bedroom', 0.57),
      ];
      expect(TaskRelevance.evaluate(keywords: keywords, labels: labels).verdict, ScanVerdict.match);
      final flagged = TaskRelevance.evaluate(keywords: keywords, labels: labels, screenLikelihood: 0.6);
      expect(flagged.isPhotoOfScreen, isTrue);
      expect(flagged.verdict, isNot(ScanVerdict.match));
      // A weak hint only nudges the score.
      final weak = TaskRelevance.evaluate(keywords: keywords, labels: labels, screenLikelihood: 0.15);
      expect(weak.isPhotoOfScreen, isFalse);
      expect(weak.verdict, ScanVerdict.match);
    });

    test('a screen warning survives when nothing is recognized', () {
      final result = TaskRelevance.evaluate(
        keywords: TaskRelevance.extractKeywords(title: 'Make the bed', iconKey: 'bed'),
        labels: const [],
        screenLikelihood: 0.6,
      );
      expect(result.verdict, ScanVerdict.unclassified);
      expect(result.isPhotoOfScreen, isTrue);
    });

    test('screens are fine when the task is about one', () {
      final result = TaskRelevance.evaluate(
        keywords: TaskRelevance.extractKeywords(title: 'Dust the computer desk'),
        labels: const [ScanLabel('computer', 0.8)],
      );
      expect(result.isPhotoOfScreen, isFalse);
      expect(result.verdict, ScanVerdict.match);
    });

    test('nothing confident enough is unclassified', () {
      final result = TaskRelevance.evaluate(
        keywords: bedroom,
        labels: const [ScanLabel('bed', 0.05)],
      );
      expect(result.verdict, ScanVerdict.unclassified);
      expect(result.score, 0);
    });

    test('no keywords leaves it to the parent', () {
      final result = TaskRelevance.evaluate(
        keywords: const [],
        labels: const [ScanLabel('bed', 0.9)],
      );
      expect(result.verdict, ScanVerdict.uncertain);
    });

    test('score stays within 0..1 and survives a Firestore round trip', () {
      final result = TaskRelevance.evaluate(
        keywords: bedroom,
        labels: const [ScanLabel('bed', 1), ScanLabel('bedroom', 1), ScanLabel('room', 1), ScanLabel('floor', 1)],
      );
      expect(result.score, inInclusiveRange(0, 1));
      final copy = TaskScanResult.fromMap(result.toMap())!;
      expect(copy.verdict, result.verdict);
      expect(copy.score, closeTo(result.score, 0.001));
      expect(copy.matches.length, result.matches.length);
      expect(copy.labels.first.label, result.labels.first.label);
      expect(copy.flags, result.flags);
    });
  });
}
