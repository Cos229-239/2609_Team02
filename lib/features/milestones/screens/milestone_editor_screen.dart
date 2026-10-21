import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/family_milestone.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/milestone_rules.dart';
import '../../../core/services/milestone_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/help_tip.dart';
import '../../../shared/widgets/number_stepper.dart';

const List<String> _illustrations = ['🎡', '🎢', '🎬', '🍕', '🏖️', '🏕️', '🎳', '🦁', '🍦', '🎉', '🏰', '🚀'];
const List<String> _rewardIcons = ['🎁', '🎟️', '🍿', '🍔', '🍰', '🎮', '🧸', '⛱️', '🚲', '🎨', '📚', '🏆'];

/// Suggestions so a parent can start from a familiar idea.
const List<(String, String, String)> _ideas = [
  ('Amusement park day', '🎢', '🎟️'),
  ('Family movie night', '🎬', '🍿'),
  ('Special family dinner', '🍕', '🍔'),
  ('Day at the beach', '🏖️', '⛱️'),
];

/// Parent: create a family goal, or edit [milestoneId].
class MilestoneEditorScreen extends StatefulWidget {
  const MilestoneEditorScreen({super.key, this.milestoneId});

  final String? milestoneId;

  @override
  State<MilestoneEditorScreen> createState() => _MilestoneEditorScreenState();
}

class _MilestoneEditorScreenState extends State<MilestoneEditorScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _reward = TextEditingController();
  String _illustration = _illustrations.first;
  String _rewardIcon = _rewardIcons.first;
  late DateTime _startDay;
  late DateTime _deadlineDay;
  int _boardLength = FamilyMilestone.defaultBoardLength;
  int _spacesPerTask = 1;
  MilestoneEligibility _eligibility = const MilestoneEligibility();
  Set<String> _participants = {};
  FamilyMilestone? _existing;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.milestoneId != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDay = DateTime(now.year, now.month, now.day);
    _deadlineDay = _startDay.add(const Duration(days: 14));
    final existing = widget.milestoneId == null ? null : context.read<MilestoneService>().byId(widget.milestoneId!);
    if (existing != null) {
      _existing = existing;
      _title.text = existing.title;
      _description.text = existing.description;
      _reward.text = existing.rewardTitle;
      _illustration = existing.illustration;
      _rewardIcon = existing.rewardIcon;
      _startDay = MilestoneRules.startOfDay(existing.startsAt);
      _deadlineDay = existing.deadlineDay;
      _boardLength = existing.boardLength;
      _spacesPerTask = existing.spacesPerTask;
      _eligibility = existing.eligibility;
      _participants = existing.participantIds.toSet();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _reward.dispose();
    super.dispose();
  }

  FamilyMilestone _draft() {
    final base = _existing ??
        FamilyMilestone(id: '', title: '', rewardTitle: '', startsAt: _startDay, endsAt: _startDay);
    return base.copyWith(
      title: _title.text.trim(),
      description: _description.text.trim(),
      illustration: _illustration,
      rewardTitle: _reward.text.trim(),
      rewardIcon: _rewardIcon,
      startsAt: MilestoneRules.startOfDay(_startDay),
      endsAt: MilestoneRules.endOfDeadlineDay(_deadlineDay),
      boardLength: _boardLength,
      spacesPerTask: _spacesPerTask,
      eligibility: _eligibility,
      participantIds: _participants.toList(),
    );
  }

  Future<void> _save() async {
    final service = context.read<MilestoneService>();
    final draft = _draft();
    final problem = MilestoneService.validate(draft);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEditing) {
        await service.update(draft);
      } else {
        await service.create(draft);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDay({required bool deadline}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = deadline ? _deadlineDay : _startDay;
    final first = deadline ? _startDay : (_isEditing ? DateTime(2020) : today);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: today.add(const Duration(days: 366)),
    );
    if (picked == null) return;
    setState(() {
      if (deadline) {
        _deadlineDay = picked;
      } else {
        _startDay = picked;
        if (_deadlineDay.isBefore(_startDay)) _deadlineDay = _startDay;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final theme = Theme.of(context);
    final days = DateFormat('EEE, MMM d');
    final minLength = _existing == null
        ? FamilyMilestone.minBoardLength
        : (_existing!.position > FamilyMilestone.minBoardLength ? _existing!.position : FamilyMilestone.minBoardLength);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Family Goal' : 'New Family Goal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEditing) ...[
              Text('Pick an idea or make your own', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (title, art, icon) in _ideas)
                    ActionChip(
                      avatar: Text(art),
                      label: Text(title),
                      onPressed: () => setState(() {
                        _title.text = title;
                        _reward.text = title;
                        _illustration = art;
                        _rewardIcon = icon;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            TextField(
              controller: _title,
              maxLength: FamilyMilestone.titleMaxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Goal name', hintText: 'e.g. Amusement park day'),
            ),
            TextField(
              controller: _description,
              maxLines: 2,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 4),
            Text('Picture', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            _EmojiChoices(choices: _illustrations, selected: _illustration, onSelected: (e) => setState(() => _illustration = e)),
            const SizedBox(height: 20),
            HeadingWithHelp(
              heading: Text('Shared reward', style: theme.textTheme.titleMedium),
              helpTitle: 'Shared reward',
              help: 'What the whole family unlocks together when the game piece reaches the finish.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reward,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Reward', hintText: 'e.g. A day at the amusement park'),
            ),
            _EmojiChoices(choices: _rewardIcons, selected: _rewardIcon, onSelected: (e) => setState(() => _rewardIcon = e)),
            const SizedBox(height: 20),
            Text('When', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.flag_outlined),
                    label: Text('Starts ${days.format(_startDay)}'),
                    onPressed: (_existing?.position ?? 0) > 0 ? null : () => _pickDay(deadline: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text('Deadline ${days.format(_deadlineDay)}'),
              onPressed: () => _pickDay(deadline: true),
            ),
            const SizedBox(height: 4),
            Text(
              'Tasks finished from the start day through the deadline count. '
              'Approve them within 2 days after the deadline.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Text('Board', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            NumberStepper(
              label: 'Spaces to the finish',
              icon: Icons.route_outlined,
              iconColor: AppColors.primaryBlue,
              value: _boardLength,
              step: 1,
              min: minLength,
              max: FamilyMilestone.maxBoardLength,
              onChanged: (v) => setState(() => _boardLength = v),
            ),
            const SizedBox(height: 8),
            NumberStepper(
              label: 'Spaces per approved task',
              icon: Icons.directions_walk,
              iconColor: AppColors.growthGreen,
              value: _spacesPerTask,
              step: 1,
              min: 1,
              max: FamilyMilestone.maxSpacesPerTask,
              onChanged: (v) => setState(() => _spacesPerTask = v),
            ),
            const SizedBox(height: 4),
            Text(
              'About ${(_boardLength / _spacesPerTask).ceil()} approved tasks to reach the goal.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Text('Which tasks count?', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('One-time tasks'),
              value: _eligibility.oneTimeTasks,
              onChanged: (v) => setState(() => _eligibility = _eligibility.copyWith(oneTimeTasks: v)),
            ),
            const Text('Repeating tasks'),
            const SizedBox(height: 6),
            SegmentedButton<RepeatingEligibility>(
              segments: const [
                ButtonSegment(value: RepeatingEligibility.all, label: Text('All')),
                ButtonSegment(value: RepeatingEligibility.selected, label: Text('Some')),
                ButtonSegment(value: RepeatingEligibility.none, label: Text('None')),
              ],
              selected: {_eligibility.repeating},
              onSelectionChanged: (s) => setState(() => _eligibility = _eligibility.copyWith(repeating: s.first)),
            ),
            if (_eligibility.repeating == RepeatingEligibility.selected) ...[
              const SizedBox(height: 6),
              if (db.schedules.isEmpty)
                Text('No repeating tasks yet.', style: theme.textTheme.bodySmall)
              else
                for (final schedule in db.schedules)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(schedule.title),
                    subtitle: Text(schedule.describe()),
                    value: _eligibility.scheduleIds.contains(schedule.id),
                    onChanged: (v) => setState(() {
                      final ids = {..._eligibility.scheduleIds};
                      v == true ? ids.add(schedule.id) : ids.remove(schedule.id);
                      _eligibility = _eligibility.copyWith(scheduleIds: ids.toList());
                    }),
                  ),
            ],
            const SizedBox(height: 20),
            HeadingWithHelp(
              heading: Text('Who plays?', style: theme.textTheme.titleMedium),
              helpTitle: 'Who plays?',
              help: 'Leave everyone unselected and every child\'s approved tasks move the family forward.',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Every child'),
                  selected: _participants.isEmpty,
                  onSelected: (_) => setState(() => _participants = {}),
                ),
                for (final child in db.children)
                  FilterChip(
                    avatar: Text(child.avatarEmoji),
                    label: Text(child.name),
                    selected: _participants.contains(child.id),
                    onSelected: (v) => setState(() {
                      _participants = {..._participants};
                      v ? _participants.add(child.id) : _participants.remove(child.id);
                    }),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: _isEditing ? 'Save Changes' : 'Start the Family Goal',
              icon: _isEditing ? Icons.save_outlined : Icons.flag,
              variant: AppButtonVariant.success,
              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiChoices extends StatelessWidget {
  const _EmojiChoices({required this.choices, required this.selected, required this.onSelected});

  final List<String> choices;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in choices)
          Semantics(
            button: true,
            selected: e == selected,
            label: 'Picture $e',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(e),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: e == selected ? AppColors.primaryBlue.withValues(alpha: 0.15) : context.mutedFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: e == selected ? AppColors.primaryBlue : Colors.transparent, width: 2),
                ),
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            ),
          ),
      ],
    );
  }
}
