import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../models/task_proof.dart';
import 'task_relevance.dart';

abstract class ImageLabeler {
  String get engine;

  Future<List<ScanLabel>?> classify(String imagePath);

  Future<double?> screenLikelihood(String imagePath);

  Future<Map<String, Map<String, double>>> similarities(List<String> keywords, List<String> labels);
}

class AppleVisionLabeler implements ImageLabeler {
  const AppleVisionLabeler();

  static const MethodChannel _channel = MethodChannel('famotive/vision');

  @override
  String get engine => 'apple-vision';

  @override
  Future<List<ScanLabel>?> classify(String imagePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      final raw = await _channel.invokeListMethod<Object?>('classifyImage', {'path': imagePath});
      if (raw == null) return null;
      final labels = <ScanLabel>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final id = item['identifier'];
        final confidence = item['confidence'];
        if (id is! String || confidence is! num) continue;
        labels.add(ScanLabel(TaskRelevance.normalizeLabel(id), confidence.toDouble()));
      }
      return labels;
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('AppleVisionLabeler.classify: $e');
      return null;
    }
  }

  @override
  Future<double?> screenLikelihood(String imagePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('screenCheck', {'path': imagePath});
      if (kDebugMode) debugPrint('AppleVisionLabeler.screenCheck: $raw');
      final value = raw?['likelihood'];
      return value is num ? value.toDouble().clamp(0.0, 1.0) : null;
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('AppleVisionLabeler.screenLikelihood: $e');
      return null;
    }
  }

  @override
  Future<Map<String, Map<String, double>>> similarities(List<String> keywords, List<String> labels) async {
    if (keywords.isEmpty || labels.isEmpty) return const {};
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'wordSimilarities',
        {'keywords': keywords, 'labels': labels},
      );
      final out = <String, Map<String, double>>{};
      raw?.forEach((keyword, row) {
        if (row is! Map) return;
        final parsed = <String, double>{};
        row.forEach((label, value) {
          if (label is String && value is num) parsed[label] = value.toDouble();
        });
        if (parsed.isNotEmpty) out[keyword] = parsed;
      });
      return out;
    } on MissingPluginException {
      return const {};
    } catch (e) {
      debugPrint('AppleVisionLabeler.similarities: $e');
      return const {};
    }
  }
}

class TaskPhotoScanner {
  const TaskPhotoScanner({this.labeler = const AppleVisionLabeler()});

  final ImageLabeler labeler;

  Future<TaskScanResult> scan(
    TaskModel task,
    String imagePath, {
    double? depthScreenLikelihood,
    DateTime? now,
  }) async {
    final keywords = TaskRelevance.extractKeywords(
      title: task.title,
      description: task.description,
      iconKey: task.icon,
    );
    final at = now ?? DateTime.now();
    final screenFuture = labeler.screenLikelihood(imagePath);
    final labels = await labeler.classify(imagePath);
    final pixelScreen = await screenFuture;
    final screen = [pixelScreen, depthScreenLikelihood].whereType<double>().fold<double?>(
          null,
          (best, v) => best == null || v > best ? v : best,
        );
    if (labels == null) {
      return TaskScanResult.unavailable(keywords: [for (final k in keywords) k.word], at: at);
    }

    final usable = labels.where((l) => l.confidence >= TaskRelevance.minLabelConfidence).toList();
    final cosine = await labeler.similarities(
      [for (final k in keywords) k.word],
      [for (final l in usable) l.label],
    );
    final result = TaskRelevance.evaluate(
      keywords: keywords,
      labels: labels,
      cosine: cosine,
      screenLikelihood: screen ?? 0,
      engine: labeler.engine,
      now: at,
    );
    if (kDebugMode) {
      debugPrint('TaskPhotoScanner: "${task.title}" keywords=$keywords '
          'labels=${labels.take(8).map((l) => '${l.label}:${l.confidence.toStringAsFixed(2)}').join(', ')} '
          'matches=${result.matches.map((m) => '${m.keyword}~${m.label}:${m.similarity.toStringAsFixed(2)}').join(', ')} '
          'screen=${screen?.toStringAsFixed(2)} cosine=$cosine flags=${result.flags} '
          '→ ${result.verdict.name} ${result.scorePercent}');
    }
    return result;
  }
}
