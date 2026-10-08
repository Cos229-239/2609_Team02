import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/utils/legal_links.dart';
import '../../../shared/widgets/app_card.dart';
import '../widgets/current_password_prompt.dart';

/// Settings → Account Settings → Delete Account.
///
/// Asks the server what deleting would do (households removed, child
/// logins removed, or what has to happen first), then re-authenticates and
/// deletes. See AuthService.deleteAccount and functions/src/account/.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  late Future<AccountDeletionPreview> _preview;
  bool _understood = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _preview = context.read<AuthService>().previewAccountDeletion();
  }

  void _reload() => setState(() => _preview = context.read<AuthService>().previewAccountDeletion());

  Future<void> _delete() async {
    final auth = context.read<AuthService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    String? password;
    if (auth.hasPasswordLogin) {
      password = await CurrentPasswordPrompt.show(
        context,
        message: 'Enter your password to permanently delete your account.',
      );
      if (password == null) return;
    }

    setState(() => _deleting = true);
    try {
      final confirmed = await auth.confirmIdentity(password: password);
      if (!confirmed) return;
      await auth.deleteAccount();
      navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      messenger.showSnackBar(const SnackBar(content: Text('Your account was deleted.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<AuthService>().currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Delete Account')),
      body: SafeArea(
        child: FutureBuilder<AccountDeletionPreview>(
          future: _preview,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Message(
                icon: Icons.cloud_off_outlined,
                text: snap.error.toString().replaceFirst('Exception: ', ''),
                action: TextButton(onPressed: _reload, child: const Text('Try again')),
              );
            }
            final preview = snap.data!;
            if (preview.forbidden != null) {
              return _Message(icon: Icons.block, text: preview.forbidden!);
            }

            return ListView(
              padding: const EdgeInsets.all(AppConstants.spaceMd),
              children: [
                Text('This permanently deletes your Famotive account.', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _Bullet('Your login and profile${user?.isChild ?? false ? ', XP and coins' : ''}'),
                if (user?.isChild ?? false) const _Bullet('Your tasks and reward history'),
                const _Bullet('Notification settings and device tokens'),
                for (final name in preview.leftHouseholds) _Bullet('You leave $name (the household stays)'),
                for (final name in preview.deletedHouseholds)
                  _Bullet('$name is deleted for everyone: its tasks, repeating tasks, rewards and history', danger: true),
                for (final name in preview.deletedAccounts)
                  _Bullet("$name's child account is deleted (you created it and it's in no other household)",
                      danger: true),
                const SizedBox(height: 8),
                Text(
                  "This can't be undone. Backups are purged within 90 days.",
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
                if ((user?.premium.isActive ?? false) && (user?.premium.willRenew ?? false)) ...[
                  const SizedBox(height: 8),
                  _Bullet(
                    "Deleting your account doesn't cancel your Premium subscription. Cancel it in your "
                    "${user?.premium.platform == 'android' ? 'Google Play' : 'App Store'} account settings "
                    "first so you aren't charged again.",
                    danger: true,
                  ),
                ],
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                  onPressed: () => LegalLinks.openPrivacy(context),
                  child: const Text('How we handle your data'),
                ),
                if (preview.blockers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.info_outline, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Before you can delete', style: theme.textTheme.titleSmall),
                        ]),
                        const SizedBox(height: 8),
                        for (final b in preview.blockers) Text(b),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.family, (route) => false),
                          child: const Text('Go to Family'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _understood,
                    onChanged: _deleting ? null : (v) => setState(() => _understood = v ?? false),
                    title: const Text('I understand this is permanent'),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _understood && !_deleting ? _delete : null,
                      child: _deleting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text('Delete My Account'),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red.shade700 : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(danger ? Icons.warning_amber_rounded : Icons.remove_circle_outline, size: 18, color: color ?? Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
