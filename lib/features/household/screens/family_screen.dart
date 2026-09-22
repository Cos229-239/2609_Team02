import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/redemption.dart';
import '../../../core/models/reward.dart';
import '../../../core/models/user.dart';
import '../../../core/services/database_service.dart';
import '../../rewards/widgets/reward_editor_sheet.dart';
import '../widgets/family_member_card.dart';

/// "Family" tab: household members, the reward store, and the
/// household-wide redemption history.
///
/// This only returns the tab's content; `MainTabShell` supplies the
/// shared app bar, bottom nav bar and `SafeArea`.
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final household = db.household;

    if (household == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final parents = db.familyMembers.where((m) => m.role == UserRole.parent);
    final children = db.children;
    final unacknowledged = db.unacknowledgedRedemptions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(household.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: 2),
          Text(
            'Manage your family members and reward store',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (unacknowledged.isNotEmpty) ...[
                  _RedemptionBanner(
                    count: unacknowledged.length,
                    onDismiss: () => db.acknowledgeAllRedemptions(),
                  ),
                  const SizedBox(height: 18),
                ],
                Row(
                  children: [
                    Icon(
                      Icons.supervisor_account_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Parents',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final parent in parents) ...[
                  FamilyMemberCard(user: parent),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(
                      Icons.child_care_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Children',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final child in children) ...[
                  FamilyMemberCard(
                    user: child,
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.taskList, arguments: child.id),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.storefront, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Reward Store',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showRewardEditorSheet(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Reward'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'What kids can redeem their coins for.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 10),
                if (db.availableRewards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No rewards yet - add one above so kids have something to work toward.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    ),
                  )
                else
                  for (final reward in db.availableRewards) ...[
                    _RewardManagementRow(reward: reward),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.receipt_long, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Transaction History',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Every reward redeemed by any child, most recent first.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 10),
                if (db.redemptions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No rewards redeemed yet.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    ),
                  )
                else
                  for (final redemption in db.redemptions) ...[
                    _TransactionRow(redemption: redemption, childName: db.userById(redemption.childId)?.name ?? 'A family member'),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 12),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showInviteCodeDialog(context, household.inviteCode),
            icon: const Icon(Icons.person_add_alt, size: 20),
            label: const Text(
              'Add Family Member',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF2563EB),
              width: 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInviteCodeDialog(BuildContext context, String? inviteCode) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: const Row(
          children: [
            Icon(Icons.group_add_rounded, size: 24),
            SizedBox(width: 10),
            Text(
              'Invite Family Member',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Text(
          inviteCode == null
              ? 'No invite code available yet.'
              : 'Share this code with a family member so they can join your household:\n\n$inviteCode',
          style: const TextStyle(
            fontSize: 15,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Close',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RedemptionBanner extends StatelessWidget {
  const _RedemptionBanner({required this.count, required this.onDismiss});

  final int count;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? '1 reward was just redeemed - see it below.'
                  : '$count rewards were just redeemed - see them below.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onDismiss,
            child: const Text('Mark Seen'),
          ),
        ],
      ),
    );
  }
}

class _RewardManagementRow extends StatelessWidget {
  const _RewardManagementRow({required this.reward});

  final Reward reward;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Reward?'),
        content: Text('This removes "${reward.title}" from the store. Past redemptions are kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<DatabaseService>().deleteReward(reward.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Row(
        children: [
          Text(reward.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reward.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                Row(
                  children: [
                    Icon(Icons.monetization_on, size: 13, color: Colors.amber.shade700),
                    const SizedBox(width: 2),
                    Text('${reward.coinCost} coins', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => showRewardEditorSheet(context, existing: reward),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.redemption, required this.childName});

  final Redemption redemption;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = DateFormat('MMM d, yyyy • h:mm a').format(redemption.redeemedAt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: redemption.acknowledgedByParent ? Colors.white : Colors.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text(redemption.rewardIcon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$childName redeemed "${redemption.rewardTitle}"',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(formatted, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monetization_on, size: 14, color: Colors.amber.shade700),
              const SizedBox(width: 2),
              Text('-${redemption.coinCost}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}
