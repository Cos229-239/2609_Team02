import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/app_card.dart';

/// "Notifications" — opt-in/out sliders for email and push notifications.
/// TODO: wire these up to a backend; for now they just toggle in the UI.

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  bool _emailNotifications = true;
  bool _pushNotifications = true;

  @override
  Widget build(BuildContext context) {
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
                    secondary: const Icon(Icons.mail_outline),
                    title: const Text('Email Notifications'),
                    subtitle: const Text('Task approvals, reminders and family updates'),
                    value: _emailNotifications,
                    onChanged: (value) => setState(() => _emailNotifications = value),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_none),
                    title: const Text('Push Notifications'),
                    subtitle: const Text('Alerts on this device for new and completed tasks'),
                    value: _pushNotifications,
                    onChanged: (value) => setState(() => _pushNotifications = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Text(
              "These preferences are a preview — Famotive doesn't send emails or "
              "push notifications yet.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
