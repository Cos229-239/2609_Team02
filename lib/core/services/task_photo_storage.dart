import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class TaskPhotoStorage {
  TaskPhotoStorage({FirebaseStorage? storage}) : _storageOverride = storage;

  final FirebaseStorage? _storageOverride;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  final Map<String, Future<Uint8List?>> _bytesCache = {};
  static const int maxDownloadBytes = 10 * 1024 * 1024;

  static String pathFor({required String householdId, required String taskId, required DateTime at}) =>
      'households/$householdId/taskPhotos/$taskId/${at.millisecondsSinceEpoch}.jpg';

  Future<String> upload({
    required String householdId,
    required String taskId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    final path = pathFor(householdId: householdId, taskId: taskId, at: DateTime.now());
    final task = _storage.ref(path).putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg', customMetadata: {'taskId': taskId}),
        );
    final sub = onProgress == null
        ? null
        : task.snapshotEvents.listen((s) {
            if (s.totalBytes > 0) onProgress(s.bytesTransferred / s.totalBytes);
          }, onError: (_) {});
    try {
      await task;
    } finally {
      await sub?.cancel();
    }
    return path;
  }

  Future<Uint8List?> download(String path) =>
      _bytesCache.putIfAbsent(path, () => _storage.ref(path).getData(maxDownloadBytes)).catchError((Object e) {
        _bytesCache.remove(path);
        throw e;
      });
}
