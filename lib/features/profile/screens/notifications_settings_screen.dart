import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/widgets/app_card.dart';

/// "Notifications" — push notification opt-in (synced to the user's
/// profile, so it applies to every device they're signed in on) and the
/// still-unimplemented email toggle.
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  // TODO: wire up email notifications to a backend.
  bool _emailNotifications = true;
  bool _savingPush = false;

  Future<void> _setPush(bool enabled) async {
    final auth = context.read<AuthService>();
    final notifications = context.read<NotificationService?>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _savingPush = true);
    try {
      await auth.setPushNotificationsEnabled(enabled);
      if (enabled && notifications != null) {
        final granted = await notifications.registerCurrentUser();
        if (!granted) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Notifications are blocked for Famotive. Turn them on in your device settings.'),
          ));
        }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _savingPush = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final pushEnabled = user?.pushNotificationsEnabled ?? true;
    final isParent = user?.isParent ?? false;

    final pushEvents = isParent
        ? const [
            'A child accepts a task from the task pool',
            'A child completes a task and it needs approval',
            'A child redeems a reward',
          ]
        : const [
            'A new task is added or assigned to you',
            'A task is due today or past due',
            'A parent approves your task',
          ];

    final smallGrey = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceSm),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_none),
                    title: const Text('Push Notifications'),
                    subtitle: Text(isParent
                        ? 'Alerts when your kids accept or finish tasks and redeem rewards'
                        : 'Alerts for new tasks, due dates and approvals'),
                    value: pushEnabled,
                    onChanged: _savingPush || user == null ? null : _setPush,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.mail_outline),
                    title: const Text('Email Notifications'),
                    subtitle: const Text('Task approvals, reminders and family updates'),
                    value: _emailNotifications,
                    onChanged: (value) => setState(() => _emailNotifications = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Text("You'll get a push notification when:", style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppConstants.spaceXs),
            for (final event in pushEvents)
              Padding(
                padding: const EdgeInsets.only(top: AppConstants.spaceXs),
                child: Text('•  $event', style: Theme.of(context).textTheme.bodyMedium),
              ),
            const SizedBox(height: AppConstants.spaceMd),
            Text(
              "Push notifications apply to every device you're signed in on. "
              "Email notifications are a preview — Famotive doesn't send emails yet.",
              style: smallGrey,
            ),
          ],
        ),
      ),
    );
  }
}
