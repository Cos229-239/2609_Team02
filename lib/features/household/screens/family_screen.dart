import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/join_request.dart';
import '../../../core/models/redemption.dart';
import '../../../core/models/reward.dart';
import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../rewards/widgets/reward_editor_sheet.dart';
import '../widgets/add_child_sheet.dart';
import '../widgets/family_member_card.dart';

/// "Family" tab: household members (with admin tools: approve join
/// requests, remove members, hand over admin), adding a child account, the
/// reward store, and the household-wide redemption history.
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
    final me = context.watch<AuthService>().currentUser;
    final isAdmin = household.isAdmin(me?.id);
    final adminName = db.userById(household.ownerId ?? '')?.name;

    String? badgeFor(AppUser member) {
      if (household.isAdmin(member.id)) return 'Admin';
      if (member.id == me?.id) return 'You';
      return null;
    }

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
            isAdmin
                ? "You're the admin: you approve anyone who asks to join."
                : (adminName == null ? 'Manage your family members and reward store' : 'Admin: $adminName'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (db.joinRequests.isNotEmpty) ...[
                  _JoinRequestsSection(requests: db.joinRequests, isAdmin: isAdmin),
                  const SizedBox(height: 18),
                ],
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
                  FamilyMemberCard(
                    user: parent,
                    badge: badgeFor(parent),
                    trailing: _MemberMenu(member: parent, isAdmin: isAdmin, meId: me?.id, isOwner: household.isAdmin(parent.id)),
                  ),
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
                    badge: badgeFor(child),
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.taskList, arguments: child.id),
                    trailing: _MemberMenu(member: child, isAdmin: isAdmin, meId: me?.id, isOwner: false),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showAddChildSheet(context),
                  icon: const Icon(Icons.child_care, size: 20),
                  label: const Text(
                    'Add Child',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: _bottomButtonStyle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showInviteCodeDialog(context, household.inviteCode),
                  icon: const Icon(Icons.person_add_alt, size: 20),
                  label: const Text(
                    'Invite',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: _bottomButtonStyle,
                ),
              ),
            ],
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
              : 'Share this code with a family member (another parent, or a child '
                  'who already has an account). They enter it under Settings > '
                  'Households, and the household admin approves them before they '
                  'can see anything:\n\n$inviteCode',
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

final _bottomButtonStyle = OutlinedButton.styleFrom(
  padding: const EdgeInsets.symmetric(vertical: 13),
  foregroundColor: const Color(0xFF2563EB),
  side: const BorderSide(color: Color(0xFF2563EB), width: 1),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

/// People who entered the invite code and are waiting to be let in. Only
/// the admin can approve or decline (rules enforce this too).
class _JoinRequestsSection extends StatelessWidget {
  const _JoinRequestsSection({required this.requests, required this.isAdmin});

  final List<JoinRequest> requests;
  final bool isAdmin;

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_reg_outlined, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Text('Asking to join', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isAdmin
                ? "Only approve people you know - they'll see your family's tasks and rewards."
                : 'Waiting for the household admin to approve.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          for (final r in requests)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(r.avatarEmoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.name} (${r.role == UserRole.parent ? 'Parent' : 'Child'})',
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        Text(r.email, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  if (isAdmin) ...[
                    IconButton(
                      tooltip: 'Decline',
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _run(
                        context,
                        () => context.read<DatabaseService>().declineJoinRequest(r),
                        '${r.name}\'s request was declined.',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Approve',
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () => _run(
                        context,
                        () => context.read<DatabaseService>().approveJoinRequest(r),
                        '${r.name} joined the household!',
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Per-member actions: the admin can remove anyone (but themself) and make
/// another parent admin; other parents can remove children.
class _MemberMenu extends StatelessWidget {
  const _MemberMenu({required this.member, required this.isAdmin, required this.meId, required this.isOwner});

  final AppUser member;
  final bool isAdmin;
  final String? meId;

  /// [member] is the household's admin.
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthService>().currentUser;
    final isSelf = member.id == meId;
    final canRemove = !isSelf && !isOwner && (isAdmin || ((me?.isParent ?? false) && member.isChild));
    final canMakeAdmin = isAdmin && !isSelf && member.isParent;
    if (!canRemove && !canMakeAdmin) return const SizedBox(width: 8);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.grey),
      onSelected: (value) {
        if (value == 'remove') _confirmRemove(context);
        if (value == 'admin') _confirmMakeAdmin(context);
      },
      itemBuilder: (_) => [
        if (canMakeAdmin)
          const PopupMenuItem(
            value: 'admin',
            child: Row(children: [Icon(Icons.verified_user_outlined, size: 20), SizedBox(width: 10), Text('Make admin')]),
          ),
        if (canRemove)
          const PopupMenuItem(
            value: 'remove',
            child: Row(children: [
              Icon(Icons.person_remove_outlined, size: 20, color: Colors.red),
              SizedBox(width: 10),
              Text('Remove from household', style: TextStyle(color: Colors.red)),
            ]),
          ),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final db = context.read<DatabaseService>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${member.name}?'),
        content: Text(
          member.isChild
              ? "${member.name}'s unfinished tasks here go back to the household pool. "
                  'Their XP and coins stay with their account.'
              : '${member.name} will no longer see this household.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await db.removeMember(member.id);
      messenger.showSnackBar(SnackBar(content: Text('${member.name} was removed.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _confirmMakeAdmin(BuildContext context) async {
    final db = context.read<DatabaseService>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Make ${member.name} the admin?'),
        content: const Text(
          'There is one admin per household. They approve join requests and manage '
          "adults. You'll stay in the household as a parent.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Make Admin')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await db.transferAdmin(member.id);
      messenger.showSnackBar(SnackBar(content: Text('${member.name} is now the admin.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
