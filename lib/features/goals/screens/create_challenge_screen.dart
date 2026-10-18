import 'package:flutter/material.dart';

import '../../../core/models/goal.dart';
import '../models/challenge_draft.dart';
import 'challenge_task_selection_screen.dart';
import 'review_challenge_screen.dart';

import 'package:provider/provider.dart';

import '../../../core/services/database_service.dart';

class CreateChallengeScreen extends StatefulWidget {
  const CreateChallengeScreen({super.key});

  @override
  State<CreateChallengeScreen> createState() => _CreateChallengeScreenState();
}

class _CreateChallengeScreenState extends State<CreateChallengeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  GoalType _selectedType = GoalType.family;
  GoalMetric _selectedMetric = GoalMetric.tasksCompleted;
  GoalPeriod _selectedPeriod = GoalPeriod.weekly;
  final Set<String> _selectedParticipantIds = <String>{};

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String? _validateParticipants() {
    if (_selectedType == GoalType.individual &&
        _selectedParticipantIds.length != 1) {
      return 'Select exactly one child for an individual challenge.';
    }

    if (_selectedType == GoalType.team && _selectedParticipantIds.length < 2) {
      return 'Select at least two children for a team challenge.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final children = context.watch<DatabaseService>().children;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Challenge')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            Text(
              'Challenge Details',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Set up a goal for your family to work toward.'),
            const SizedBox(height: 24),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Challenge Name',
                hintText: 'e.g. Kitchen Cleanup Week',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 100,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a challenge name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<GoalType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Challenge Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: GoalType.family, child: Text('Family')),
                DropdownMenuItem(
                  value: GoalType.individual,
                  child: Text('Individual'),
                ),
                DropdownMenuItem(value: GoalType.team, child: Text('Team')),
              ],
              onChanged: (value) {
                if (value != null && value != _selectedType) {
                  setState(() {
                    _selectedType = value;
                    _selectedParticipantIds.clear();
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<GoalMetric>(
              initialValue: _selectedMetric,
              decoration: const InputDecoration(
  labelText: 'Challenge Goal',
  helperText: 'Choose how this challenge will be completed.',
  border: OutlineInputBorder(),
),
              items: const [
  DropdownMenuItem(
    value: GoalMetric.tasksCompleted,
    child: Text('Complete Specific Chores'),
  ),
  DropdownMenuItem(
    value: GoalMetric.xpEarned,
    child: Text('Earn XP'),
  ),
  DropdownMenuItem(
    value: GoalMetric.coinsEarned,
    child: Text('Earn Coins'),
  ),
],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedMetric = value;
                  });
                }
              },
            ),
          
            const SizedBox(height: 16),
            DropdownButtonFormField<GoalPeriod>(
              initialValue: _selectedPeriod,
              decoration: const InputDecoration(
                labelText: 'Challenge Duration',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: GoalPeriod.daily, child: Text('Daily')),
                DropdownMenuItem(
                  value: GoalPeriod.weekly,
                  child: Text('Weekly'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedPeriod = value;
                  });
                }
              },
            ),
            if (_selectedType != GoalType.family) ...[
              const SizedBox(height: 24),
              Text(
                'Participants',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _selectedType == GoalType.individual
                    ? 'Select one child for this challenge.'
                    : 'Select at least two children for this challenge.',
              ),
              const SizedBox(height: 12),
              if (children.isEmpty)
                const Text('No children are available in this household.'),
              for (final child in children)
                CheckboxListTile(
                  title: Text(child.name),
                  value: _selectedParticipantIds.contains(child.id),
                  onChanged: (selected) {
                    setState(() {
                      if (selected == true) {
                        if (_selectedType == GoalType.individual) {
                          _selectedParticipantIds.clear();
                        }
                        _selectedParticipantIds.add(child.id);
                      } else {
                        _selectedParticipantIds.remove(child.id);
                      }
                    });
                  },
                ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) {
                  return;
                }

                final participantError = _validateParticipants();

                if (participantError != null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(participantError)));
                  return;
                }

                
final draft = ChallengeDraft(
  title: _titleController.text.trim(),
  type: _selectedType,
  metric: _selectedMetric,
  targetValue: 0,
  period: _selectedPeriod,
  participantIds: List<String>.of(_selectedParticipantIds),
);


Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => _selectedMetric == GoalMetric.tasksCompleted
        ? ChallengeTaskSelectionScreen(draft: draft)
        : ReviewChallengeScreen(draft: draft),
  ),
);


              },
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
}
