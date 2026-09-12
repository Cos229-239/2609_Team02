import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/reward_tile.dart';

/// "Parents choosing rewards" — pick which reward a child should be
/// working toward for their assigned tasks.
class RewardChooseScreen extends StatefulWidget {
  const RewardChooseScreen({super.key, required this.childId});

  final String childId;

  @override
  State<RewardChooseScreen> createState() => _RewardChooseScreenState();
}

class _RewardChooseScreenState extends State<RewardChooseScreen> {
  String? _selectedRewardId;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final child = db.userById(widget.childId);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Reward')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select a reward task for ${child?.name ?? 'your child'} to complete.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: RadioGroup<String>(
                  groupValue: _selectedRewardId,
                  onChanged: (value) => setState(() => _selectedRewardId = value),
                  child: ListView.separated(
                    itemCount: db.availableRewards.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final reward = db.availableRewards[index];
                      return RewardTile(
                        reward: reward,
                        selected: _selectedRewardId == reward.id,
                        onTap: () => setState(() => _selectedRewardId = reward.id),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Confirm Rewards',
                icon: Icons.check,
                onPressed: _selectedRewardId == null
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reward assigned!')),
                        );
                        Navigator.of(context).pop();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
