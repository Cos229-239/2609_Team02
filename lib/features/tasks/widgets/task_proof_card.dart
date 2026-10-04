import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/task_proof.dart';
import '../../../core/services/task_photo_storage.dart';
import '../../../shared/widgets/app_card.dart';
import 'scan_verdict_badge.dart';

class TaskProofCard extends StatefulWidget {
  const TaskProofCard({super.key, required this.proof, this.storage});

  final TaskProof proof;
  final TaskPhotoStorage? storage;

  @override
  State<TaskProofCard> createState() => _TaskProofCardState();
}

class _TaskProofCardState extends State<TaskProofCard> {
  late final TaskPhotoStorage _storage = widget.storage ?? TaskPhotoStorage();
  Future<Uint8List?>? _photo;
  String? _loadedPath;

  void _load() {
    final path = widget.proof.photoPath;
    if (path == _loadedPath) return;
    _loadedPath = path;
    _photo = path == null ? null : _storage.download(path);
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final theme = Theme.of(context);
    final proof = widget.proof;
    final scan = proof.scan;
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Photo Proof', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (scan != null) ScanVerdictBadge(scan: scan),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: AspectRatio(aspectRatio: 4 / 3, child: _photoView(context)),
          ),
          const SizedBox(height: 10),
          Text(proof.verdict.explanation, style: theme.textTheme.bodyMedium),
          if (scan != null && scan.isPhotoOfScreen) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.tv, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Looks like a photo of a screen, not the real thing.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ],
          if (scan != null && scan.matches.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Matched:', style: muted),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final m in scan.matches)
                  _Chip(text: m.keyword == m.label ? m.label : '${m.keyword} ↔ ${m.label}', highlight: true),
              ],
            ),
          ],
          if (scan != null && scan.labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Seen in the photo:', style: muted),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final l in scan.labels.take(6)) _Chip(text: '${l.label} ${(l.confidence * 100).round()}%'),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(_footer(proof), style: muted?.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _photoView(BuildContext context) {
    final placeholder = Container(color: Colors.grey.shade100);
    if (!widget.proof.hasPhoto) {
      return Container(
        color: Colors.grey.shade100,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          'The photo was deleted after ${AppConstants.taskPhotoRetentionDays} days.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Stack(fit: StackFit.expand, children: [placeholder, const Center(child: CircularProgressIndicator())]);
        }
        final bytes = snap.data;
        if (snap.hasError || bytes == null) {
          return Container(
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _loadedPath = null;
              }),
              icon: const Icon(Icons.refresh),
              label: const Text("Couldn't load the photo - retry"),
            ),
          );
        }
        return GestureDetector(
          onTap: () => _showFullScreen(context, bytes),
          child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        );
      },
    );
  }

  void _showFullScreen(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain))),
            SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _footer(TaskProof proof) {
    final fmt = DateFormat.MMMd().add_jm();
    final parts = <String>[
      'Checked on the child\'s device',
      if (proof.parentOverride) 'approved by a parent despite the check',
      if (proof.hasPhoto && proof.deleteAt != null) 'photo auto-deletes ${fmt.format(proof.deleteAt!)}',
    ];
    return parts.join(' · ');
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? Colors.green.shade700 : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
