import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/household.dart';
import '../../../core/models/join_request.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';

String _message(Object e) => e.toString().replaceFirst('Exception: ', '');

void showHouseholdSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// "Enter an invite code" card: files a join request that the household's
/// admin must approve.
class JoinHouseholdCard extends StatefulWidget {
  const JoinHouseholdCard({super.key});

  @override
  State<JoinHouseholdCard> createState() => _JoinHouseholdCardState();
}

class _JoinHouseholdCardState extends State<JoinHouseholdCard> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final name = await context.read<AuthService>().requestToJoinHousehold(code);
      if (!mounted) return;
      _controller.clear();
      showHouseholdSnack(context, 'Request sent to $name. Their admin needs to approve you.');
    } catch (e) {
      if (mounted) showHouseholdSnack(context, _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Join a household', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "Enter the invite code a parent shared with you. The household's admin "
            'will be asked to approve you.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Invite code', isDense: true),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Request'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the signed-in user's own join requests, with "Cancel".
class PendingRequestTile extends StatelessWidget {
  const PendingRequestTile({super.key, required this.request});

  final JoinRequest request;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: Colors.orange.withValues(alpha: 0.06),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.householdName ?? 'Household', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  'Waiting for the admin to approve you',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.read<AuthService>().cancelJoinRequest(request.householdId),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Asks for a name and creates a new household (the parent becomes admin).
Future<void> showCreateHouseholdDialog(BuildContext context) async {
  final auth = context.read<AuthService>();
  final controller = TextEditingController(
    text: auth.currentUser == null ? '' : "${auth.currentUser!.name.split(' ').first}'s Family",
  );
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('New Household'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Household name'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  // Not disposed here: the dialog's closing animation still uses it.
  if (name == null || name.trim().isEmpty) return;
  try {
    await auth.createHousehold(householdName: name);
    if (context.mounted) showHouseholdSnack(context, '"${name.trim()}" created - you\'re its admin.');
  } catch (e) {
    if (context.mounted) showHouseholdSnack(context, _message(e));
  }
}

/// Admin only: asks for a new name for [household] and saves it. Shown from
/// the Family tab header and Settings > Households.
Future<void> showRenameHouseholdDialog(BuildContext context, Household household) async {
  final db = context.read<DatabaseService>();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameHouseholdDialog(currentName: household.name),
  );
  if (name == null || name.trim() == household.name) return;
  try {
    await db.renameHousehold(name, householdId: household.id);
    if (context.mounted) showHouseholdSnack(context, 'Household renamed to "${name.trim()}".');
  } catch (e) {
    if (context.mounted) showHouseholdSnack(context, _message(e));
  }
}

class _RenameHouseholdDialog extends StatefulWidget {
  const _RenameHouseholdDialog({required this.currentName});

  final String currentName;

  @override
  State<_RenameHouseholdDialog> createState() => _RenameHouseholdDialogState();
}

class _RenameHouseholdDialogState extends State<_RenameHouseholdDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.currentName);

  bool get _canSave {
    final name = _controller.text.trim();
    return name.isNotEmpty && name != widget.currentName;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_canSave) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Household'),
      content: TextField(
        key: const Key('rename-household-field'),
        controller: _controller,
        autofocus: true,
        maxLength: AppConstants.householdNameMaxLength,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Household name',
          helperText: 'Everyone in the household will see the new name.',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('rename-household-save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
