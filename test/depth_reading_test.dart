import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/services/depth_camera.dart';

void main() {
  group('DepthReading.screenLikelihood', () {
    test('flat and close (a phone/monitor) is a strong screen signal', () {
      const r = DepthReading(validFraction: 0.9, meanDepth: 0.3, planeResidual: 0.008);
      expect(r.screenLikelihood, closeTo(0.85, 0.001));
    });

    test('flat but far (a wall, a TV across the room) counts less', () {
      const r = DepthReading(validFraction: 0.9, meanDepth: 1.8, planeResidual: 0.01);
      expect(r.screenLikelihood, closeTo(0.5, 0.001));
    });

    test('a real 3D scene (bed, pillows, wall) is not a screen', () {
      const r = DepthReading(validFraction: 0.95, meanDepth: 1.2, planeResidual: 0.12);
      expect(r.screenLikelihood, 0);
    });

    test('in-between residual scales down', () {
      const r = DepthReading(validFraction: 0.9, meanDepth: 0.4, planeResidual: 0.035);
      expect(r.screenLikelihood, closeTo(0.425, 0.001));
    });

    test('too little valid depth: no opinion', () {
      const r = DepthReading(validFraction: 0.2, meanDepth: 0.3, planeResidual: 0.001);
      expect(r.screenLikelihood, 0);
      expect(const DepthReading(validFraction: 0.9).screenLikelihood, 0);
    });

    test('fromMap parses the native result', () {
      final r = DepthReading.fromMap({
        'validFraction': 0.8,
        'meanDepth': 0.25,
        'planeResidual': 0.004,
        'depthSpread': 0.02,
        'accuracy': 'absolute',
      })!;
      expect(r.absolute, isTrue);
      expect(r.planeResidual, 0.004);
      expect(r.screenLikelihood, greaterThan(0.8));
      expect(DepthReading.fromMap(null), isNull);
    });
  });

  test('DepthCamera is unavailable off iOS', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await expectLater(const DepthCamera().capture(), throwsA(isA<DepthCameraUnavailable>()));
  });
}
