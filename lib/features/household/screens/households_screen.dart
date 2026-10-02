import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/household.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../widgets/household_actions.dart';

/// Settings > Households: every household the user belongs to (switch,
/// leave), their pending join requests, joining another household with an
/// invite code and (parents) creating a new one.
///
/// XP and coins belong to the child's account, so they follow a child into
/// every household.
class HouseholdsScreen extends StatelessWidget {
  const HouseholdsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final db = context.watch<DatabaseService>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Households')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Your households', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              user?.isChild ?? false
                  ? 'Your XP and coins come with you to every household.'
                  : 'Tap one to switch to it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            if (!db.membershipsLoaded)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (db.myHouseholds.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("You're not in a household yet."),
              )
            else
              for (final h in db.myHouseholds) ...[
                _HouseholdTile(household: h, active: h.id == user?.householdId, userId: user?.id),
                const SizedBox(height: 8),
              ],
            if (db.myPendingRequests.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Waiting for approval', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final r in db.myPendingRequests) ...[
                PendingRequestTile(request: r),
                const SizedBox(height: 8),
              ],
            ],
            const SizedBox(height: 16),
            const JoinHouseholdCard(),
            if (user?.isParent ?? false) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => showCreateHouseholdDialog(context),
                icon: const Icon(Icons.add_home_outlined),
                label: const Text('Create a new household'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HouseholdTile extends StatelessWidget {
  const _HouseholdTile({required this.household, required this.active, required this.userId});

  final Household household;
  final bool active;
  final String? userId;

  Future<void> _leave(BuildContext context) async {
    final auth = context.read<AuthService>();
    final db = context.read<DatabaseService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${household.name}?'),
        content: const Text(
          "You'll stop seeing its tasks and rewards. XP and coins you've earned stay with "
          'your account. To come back you\'ll need the invite code and the admin\'s approval.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final others = db.myHouseholds.where((h) => h.id != household.id).toList();
    try {
      await auth.leaveHousehold(household.id, switchTo: others.isEmpty ? null : others.first.id);
      if (context.mounted) showHouseholdSnack(context, 'You left ${household.name}.');
    } catch (e) {
      if (context.mounted) showHouseholdSnack(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = household.isAdmin(userId);
    final count = household.memberIds.length;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: active ? theme.colorScheme.primary.withValues(alpha: 0.06) : null,
      onTap: active ? null : () => context.read<AuthService>().switchHousehold(household.id),
      child: Row(
        children: [
          Icon(active ? Icons.home_rounded : Icons.home_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(household.name, style: theme.textTheme.titleMedium),
                Text(
                  [
                    '$count member${count == 1 ? '' : 's'}',
                    if (isAdmin) 'You\'re the admin',
                    if (active) 'Current',
                  ].join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'switch') context.read<AuthService>().switchHousehold(household.id);
              if (value == 'leave') _leave(context);
            },
            itemBuilder: (_) => [
              if (!active) const PopupMenuItem(value: 'switch', child: Text('Switch to this household')),
              const PopupMenuItem(
                value: 'leave',
                child: Text('Leave household', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
