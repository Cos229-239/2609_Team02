import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../widgets/profile_menu_tile.dart';

/// "Settings" tab — account info and app settings placeholders, plus
/// sign-out (which closes the sample flow loop back to the login screen).
///
/// This only returns the tab's content; `MainTabShell` supplies the
/// shared app bar, bottom nav bar and `SafeArea`.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
                  child: Text(user.avatarEmoji, style: const TextStyle(fontSize: 22)),
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
                onTap: () {},
              ),
              ProfileMenuTile(
                icon: Icons.notifications_none,
                label: 'Notifications',
                onTap: () {},
              ),
              ProfileMenuTile(
                icon: Icons.help_outline,
                label: 'Help & Support',
                onTap: () {},
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
