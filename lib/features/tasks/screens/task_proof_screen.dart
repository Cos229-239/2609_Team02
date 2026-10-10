import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/models/task_proof.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/depth_camera.dart';
import '../../../core/services/task_photo_scanner.dart';
import '../../../core/services/task_photo_storage.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../widgets/scan_verdict_badge.dart';

enum _Stage { capture, scanning, result, uploading }

class TaskProofScreen extends StatefulWidget {
  const TaskProofScreen({
    super.key,
    required this.taskId,
    this.scanner = const TaskPhotoScanner(),
    this.storage,
    this.picker,
    this.depthCamera = const DepthCamera(),
  });

  final String taskId;
  final TaskPhotoScanner scanner;
  final TaskPhotoStorage? storage;
  final ImagePicker? picker;
  final DepthCamera depthCamera;

  @override
  State<TaskProofScreen> createState() => _TaskProofScreenState();
}

class _TaskProofScreenState extends State<TaskProofScreen> {
  late final TaskPhotoStorage _storage = widget.storage ?? TaskPhotoStorage();
  late final ImagePicker _picker = widget.picker ?? ImagePicker();

  _Stage _stage = _Stage.capture;
  File? _photo;
  TaskScanResult? _scan;
  double _uploadProgress = 0;
  String? _error;

  TaskModel? _task(DatabaseService db) => db.taskById(widget.taskId);

  Future<void> _takePhoto(TaskModel task, {ImageSource source = ImageSource.camera}) async {
    setState(() => _error = null);

    double? depthScreen;
    String? path;
    if (source == ImageSource.camera) {
      try {
        final capture = await widget.depthCamera.capture();
        if (capture == null) return; // cancelled
        path = capture.path;
        depthScreen = capture.depth?.screenLikelihood;
      } on DepthCameraUnavailable {
        // No depth camera on this phone: regular picker below.
      } on DepthCameraDenied {
        if (!mounted) return;
        setState(() => _error = 'Famotive needs the camera for this. Turn it on in Settings > Famotive.');
        return;
      } catch (e) {
        debugPrint('TaskProofScreen: depth camera failed, using picker: $e');
      }
    }
    if (path == null) {
      final picked = await _pickWithPicker(source);
      if (picked == null) return;
      path = picked;
    }
    if (!mounted) return;
    await _scanPhoto(task, path, depthScreen);
  }

  Future<String?> _pickWithPicker(ImageSource source) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
    } catch (e) {
      debugPrint('TaskProofScreen: picker failed: $e');
      if (mounted) {
        setState(() => _error = "Couldn't open the camera. Check that Famotive is allowed to use it in Settings.");
      }
      return null;
    }
    return picked?.path;
  }

  Future<void> _scanPhoto(TaskModel task, String path, double? depthScreen) async {
    final file = File(path);
    setState(() {
      _photo = file;
      _scan = null;
      _stage = _Stage.scanning;
    });

    TaskScanResult scan;
    try {
      scan = await widget.scanner.scan(task, file.path, depthScreenLikelihood: depthScreen);
    } catch (e) {
      debugPrint('TaskProofScreen: scan failed: $e');
      scan = TaskScanResult.unavailable(at: DateTime.now());
    }
    if (!mounted) return;
    setState(() {
      _scan = scan;
      _stage = _Stage.result;
    });
  }

  Future<void> _submit(TaskModel task) async {
    final photo = _photo;
    final scan = _scan;
    if (photo == null || scan == null) return;
    final db = context.read<DatabaseService>();
    final householdId = db.activeHouseholdId;
    if (householdId == null) {
      setState(() => _error = 'No household is selected.');
      return;
    }

    setState(() {
      _stage = _Stage.uploading;
      _uploadProgress = 0;
      _error = null;
    });
    try {
      final path = await _storage.upload(
        householdId: householdId,
        taskId: task.id,
        file: photo,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      await db.submitTaskProof(task.id, photoPath: path, scan: scan);
      if (!mounted) return;
      await Navigator.of(context).pushReplacementNamed(AppRoutes.taskCompletion, arguments: task.id, result: true);
    } catch (e) {
      debugPrint('TaskProofScreen: submit failed: $e');
      if (!mounted) return;
      setState(() {
        _stage = _Stage.result;
        _error = e is Exception && e.toString().startsWith('Exception: ')
            ? e.toString().replaceFirst('Exception: ', '')
            : "Couldn't send your photo. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final task = _task(db);
    if (task == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Task not found.')));
    }
    final theme = Theme.of(context);

    return PopScope(
      canPop: _stage != _Stage.uploading,
      child: Scaffold(
        appBar: AppBar(title: const Text('Show Your Work')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AppCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.15),
                      child: Icon(TaskIconCatalog.resolve(task.icon).icon, color: theme.colorScheme.secondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(task.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            'Take a photo that shows this task is done.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _PhotoFrame(photo: _photo, stage: _stage, uploadProgress: _uploadProgress),
              const SizedBox(height: 16),
              if (_stage == _Stage.result && _scan != null) _ScanFeedback(scan: _scan!),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              ..._actions(task),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your photo is checked on this device. Only your parents can see it, '
                      'and it is deleted ${AppConstants.taskPhotoRetentionDays} days after you finish.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(TaskModel task) {
    switch (_stage) {
      case _Stage.capture:
        return [
          AppButton(label: 'Take Photo', icon: Icons.photo_camera, onPressed: () => _takePhoto(task)),
          // The simulator has no camera.
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _takePhoto(task, source: ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from library (debug)'),
            ),
          ],
        ];
      case _Stage.scanning:
      case _Stage.uploading:
        return const [];
      case _Stage.result:
        final verdict = _scan?.verdict ?? ScanVerdict.unavailable;
        final good = verdict == ScanVerdict.match || verdict == ScanVerdict.unavailable;
        return [
          AppButton(
            label: good ? 'Send to Parent' : 'Send Anyway',
            icon: Icons.send,
            variant: good ? AppButtonVariant.success : AppButtonVariant.primary,
            onPressed: () => _submit(task),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _takePhoto(task),
            icon: const Icon(Icons.refresh),
            label: const Text('Retake Photo'),
          ),
        ];
    }
  }
}

class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({required this.photo, required this.stage, required this.uploadProgress});

  final File? photo;
  final _Stage stage;
  final double uploadProgress;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo == null)
              Container(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceDarkRaised
                    : AppColors.surfaceLight,
                child: Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey.shade400),
              )
            else
              Image.file(photo, fit: BoxFit.cover),
            if (stage == _Stage.scanning || stage == _Stage.uploading)
              Container(
                color: Colors.black45,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (stage == _Stage.scanning)
                      const CircularProgressIndicator(color: Colors.white)
                    else
                      SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(value: uploadProgress > 0 ? uploadProgress : null),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      stage == _Stage.scanning ? 'Checking your photo…' : 'Sending to your parent…',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScanFeedback extends StatelessWidget {
  const _ScanFeedback({required this.scan});

  final TaskScanResult scan;

  @override
  Widget build(BuildContext context) {
    final (emoji, message) = scan.isPhotoOfScreen && scan.verdict != ScanVerdict.match
        ? ('📺', 'This looks like a photo of a screen. Take a photo of the real thing!')
        : switch (scan.verdict) {
      ScanVerdict.match => ('🎉', 'Nice! Your photo looks like this task.'),
      ScanVerdict.uncertain => ('🤔', "Hmm, we're not sure this photo shows the task. Try a clearer photo, or send it anyway."),
      ScanVerdict.noMatch => ('🧐', "This photo doesn't seem to show the task. Try again, or send it anyway and your parent will check."),
      ScanVerdict.unclassified => ('📷', "We couldn't tell what's in this photo. Try more light, or send it anyway."),
      ScanVerdict.unavailable => ('👀', 'Your parent will take a look at this photo.'),
    };
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: AppConstants.emojiIconXl)),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          if (scan.verdict != ScanVerdict.unavailable) ...[
            const SizedBox(height: 10),
            ScanVerdictBadge(scan: scan),
          ],
          if (kDebugMode && scan.verdict != ScanVerdict.unavailable) ...[
            const SizedBox(height: 10),
            Text(
              'Saw: ${scan.labels.map((l) => '${l.label} ${(l.confidence * 100).round()}%').join(', ')}\n'
              'Matched: ${scan.matches.map((m) => '${m.keyword}↔${m.label} ${(m.similarity * 100).round()}%').join(', ')}'
              '${scan.flags.isEmpty ? '' : '\nFlags: ${scan.flags.join(', ')}'}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
