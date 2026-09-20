import 'package:flutter/material.dart';

/// A single row in the profile/settings menu (icon, label, chevron).
class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
    ? Theme.of(context).colorScheme.error
    : Colors.black;

return ListTile(
  leading: Icon(
    icon,
    color: color,
    size: 24,
  ),
  title: Text(
    label,
    style: TextStyle(
      color: color,
      fontWeight: FontWeight.w500,
      fontSize: 16,
    ),
  ),
  trailing: destructive
      ? null
      : Icon(
          Icons.chevron_right,
          color: Colors.grey.shade400,
          size: 22,
        ),
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
  onTap: onTap,
  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
  minVerticalPadding: 10,
);
  }
}
