import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/reward.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/number_stepper.dart';

const List<String> _iconChoices = [
  '⭐', '🎮', '🌳', '🍬', '🎬', '🍕', '🎨', '📱',
  '🧸', '🎁', '🍦', '🚲', '🏖️', '🎳', '📚', '🎧',
];

/// Opens a bottom sheet to create a reward, or edit [existing] in place.
Future<void> showRewardEditorSheet(BuildContext context, {Reward? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _RewardEditorSheet(existing: existing),
  );
}

class _RewardEditorSheet extends StatefulWidget {
  const _RewardEditorSheet({this.existing});

  final Reward? existing;

  @override
  State<_RewardEditorSheet> createState() => _RewardEditorSheetState();
}

class _RewardEditorSheetState extends State<_RewardEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _icon;
  late RewardType _type;
  late int _coinCost;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _icon = existing?.icon ?? _iconChoices.first;
    _type = existing?.type ?? RewardType.activity;
    _coinCost = existing?.coinCost ?? 50;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canSave => _titleController.text.trim().isNotEmpty;

  void _save(DatabaseService db) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    if (widget.existing != null) {
      final updated = widget.existing!.copyWith(
        title: title,
        description: _descriptionController.text.trim(),
        icon: _icon,
        type: _type,
        coinCost: _coinCost,
      );
      db.updateReward(widget.existing!.id, updated);
    } else {
      db.addReward(
        Reward(
          id: 'reward-${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          description: _descriptionController.text.trim(),
          icon: _icon,
          type: _type,
          coinCost: _coinCost,
        ),
      );
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isEditing ? 'Edit Reward' : 'Add Reward',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Text('Icon:', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final icon in _iconChoices)
                  _EmojiOption(
                    emoji: icon,
                    selected: icon == _icon,
                    onTap: () => setState(() => _icon = icon),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Name:', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              autofocus: !_isEditing,
              decoration: const InputDecoration(hintText: 'e.g. Movie Night'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Description:', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'What does this reward include?'),
            ),
            const SizedBox(height: 16),
            Text('Category:', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in RewardType.values)
                  ChoiceChip(
                    label: Text(_typeLabel(type)),
                    selected: _type == type,
                    onSelected: (selected) {
                      if (selected) setState(() => _type = type);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            NumberStepper(
              label: 'Coin Cost',
              icon: Icons.monetization_on,
              iconColor: Colors.amber.shade700,
              value: _coinCost,
              step: 5,
              max: 5000,
              onChanged: (value) => setState(() => _coinCost = value),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: _isEditing ? 'Save Changes' : 'Add Reward',
              icon: _isEditing ? Icons.save_outlined : Icons.add,
              onPressed: _canSave ? () => _save(context.read<DatabaseService>()) : null,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _typeLabel(RewardType type) {
    switch (type) {
      case RewardType.points:
        return 'Bonus';
      case RewardType.screenTime:
        return 'Screen Time';
      case RewardType.activity:
        return 'Activity';
      case RewardType.treat:
        return 'Treat';
      case RewardType.badge:
        return 'Badge';
    }
  }
}

class _EmojiOption extends StatelessWidget {
  const _EmojiOption({required this.emoji, required this.selected, required this.onTap});

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}
