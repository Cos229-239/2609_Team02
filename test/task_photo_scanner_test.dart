import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/task_proof.dart';
import 'package:famotive/core/services/task_photo_scanner.dart';

class _FakeLabeler implements ImageLabeler {
  _FakeLabeler(this.labels, {this.screen});

  final List<ScanLabel>? labels;
  final Map<String, Map<String, double>> cosine = const {};
  final double? screen;
  List<String>? askedLabels;

  @override
  Future<double?> screenLikelihood(String imagePath) async => screen;

  @override
  String get engine => 'fake';

  @override
  Future<List<ScanLabel>?> classify(String imagePath) async => labels;

  @override
  Future<Map<String, Map<String, double>>> similarities(List<String> keywords, List<String> labels) async {
    askedLabels = labels;
    return cosine;
  }
}

void main() {
  const task = TaskModel(id: 't1', title: 'Clean your bedroom', icon: 'bed', requiresPhoto: true);

  test('combines Vision labels with task keywords', () async {
    final labeler = _FakeLabeler(const [ScanLabel('bed', 0.8), ScanLabel('blanket', 0.5), ScanLabel('noise', 0.01)]);
    final result = await TaskPhotoScanner(labeler: labeler).scan(task, '/tmp/x.jpg');
    expect(result.verdict, ScanVerdict.match);
    expect(result.engine, 'fake');
    expect(labeler.askedLabels, ['bed', 'blanket']);
  });

  test('a photo of a screen showing a bed is flagged, not a match', () async {
    final labeler = _FakeLabeler(const [ScanLabel('bed', 0.6), ScanLabel('bedding', 0.74)], screen: 0.6);
    final result = await TaskPhotoScanner(labeler: labeler).scan(task, '/tmp/x.jpg');
    expect(result.isPhotoOfScreen, isTrue);
    expect(result.verdict, isNot(ScanVerdict.match));
  });

  test('the depth camera can flag a screen the pixels miss', () async {
    final labeler = _FakeLabeler(const [ScanLabel('bed', 0.6), ScanLabel('bedding', 0.6)], screen: 0.0);
    final result = await TaskPhotoScanner(labeler: labeler).scan(task, '/tmp/x.jpg', depthScreenLikelihood: 0.85);
    expect(result.isPhotoOfScreen, isTrue);
    expect(result.verdict, isNot(ScanVerdict.match));
  });

  test('no classifier on this device -> unavailable, parent reviews', () async {
    final result = await TaskPhotoScanner(labeler: _FakeLabeler(null)).scan(task, '/tmp/x.jpg');
    expect(result.verdict, ScanVerdict.unavailable);
    expect(result.keywords, contains('bedroom'));
  });

  test('AppleVisionLabeler returns null off iOS / without the channel', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await const AppleVisionLabeler().classify('/tmp/x.jpg'), isNull);
    expect(await const AppleVisionLabeler().similarities(['a'], ['b']), isEmpty);
  });
}
