import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../widgets/profile_menu_tile.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Opens the device's mail app with a pre-filled support request,
  /// pre-addressed to support@famotive.org.
  Future<void> _launchSupportEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@famotive.org',
      queryParameters: {'subject': 'App Support Request'},
    );
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open your email app — reach us at support@famotive.org"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (user != null)
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(user.avatarEmoji, style: const TextStyle(fontSize: AppConstants.emojiIconMd)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        user.email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              ProfileMenuTile(
                icon: Icons.person_outline,
                label: 'Account Settings',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.accountSettings),
              ),
              ProfileMenuTile(
                icon: Icons.notifications_none,
                label: 'Notifications',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.notificationSettings),
              ),
              ProfileMenuTile(
                icon: Icons.help_outline,
                label: 'Help & Support',
                onTap: () => _launchSupportEmail(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ProfileMenuTile(
            icon: Icons.logout,
            label: 'Log Out',
            destructive: true,
            onTap: () async {
              await context.read<AuthService>().logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
              }
            },
          ),
        ),
      ],
    );
  }
}
