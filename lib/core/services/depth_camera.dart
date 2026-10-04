import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DepthReading {
  const DepthReading({
    required this.validFraction,
    this.meanDepth,
    this.planeResidual,
    this.depthSpread,
    this.absolute = false,
  });

  final double validFraction;
  final double? meanDepth;
  final double? planeResidual;
  final double? depthSpread;
  final bool absolute;

  // --- Tunables (from iPhone 18 Pro logs) --------------------------------

  static const double minValidFraction = 0.5;
  static const double flatResidual = 0.02;
  static const double sceneResidual = 0.05;
  static const double nearDepth = 0.6;

  double get screenLikelihood {
    final residual = planeResidual;
    if (validFraction < minValidFraction || residual == null) return 0;
    if (residual >= sceneResidual) return 0;
    final flatness = residual <= flatResidual
        ? 1.0
        : 1 - (residual - flatResidual) / (sceneResidual - flatResidual);
    final near = (meanDepth ?? double.infinity) <= nearDepth;
    return (flatness * (near ? 0.85 : 0.5)).clamp(0.0, 1.0);
  }

  static DepthReading? fromMap(Object? raw) {
    if (raw is! Map) return null;
    double? d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    return DepthReading(
      validFraction: d(raw['validFraction']) ?? 0,
      meanDepth: d(raw['meanDepth']),
      planeResidual: d(raw['planeResidual']),
      depthSpread: d(raw['depthSpread']),
      absolute: raw['accuracy'] == 'absolute',
    );
  }

  @override
  String toString() => 'DepthReading(valid=${validFraction.toStringAsFixed(2)}, '
      'mean=${meanDepth?.toStringAsFixed(2)}m, residual=${planeResidual?.toStringAsFixed(4)}, '
      'spread=${depthSpread?.toStringAsFixed(3)}, ${absolute ? 'absolute' : 'relative'} '
      '→ screen ${screenLikelihood.toStringAsFixed(2)})';
}

class DepthCapture {
  const DepthCapture({required this.path, this.depth});

  final String path;
  final DepthReading? depth;
}

class DepthCameraUnavailable implements Exception {
  const DepthCameraUnavailable();
}

class DepthCameraDenied implements Exception {
  const DepthCameraDenied();
}

class DepthCamera {
  const DepthCamera();

  static const MethodChannel _channel = MethodChannel('famotive/vision');

  Future<DepthCapture?> capture() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) throw const DepthCameraUnavailable();
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('captureWithDepth');
      if (raw == null) return null;
      final path = raw['path'];
      if (path is! String) return null;
      final depth = DepthReading.fromMap(raw['depth']);
      if (kDebugMode) debugPrint('DepthCamera: $depth ${raw['depth']}');
      return DepthCapture(path: path, depth: depth);
    } on MissingPluginException {
      throw const DepthCameraUnavailable();
    } on PlatformException catch (e) {
      if (e.code == 'unsupported') throw const DepthCameraUnavailable();
      if (e.code == 'camera_denied') throw const DepthCameraDenied();
      rethrow;
    }
  }
}
