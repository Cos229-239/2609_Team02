import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// A consistently padded, rounded container used for every "row" or
/// "tile" style element across the app (task rows, reward rows, family
/// member cards, summary tiles). Optionally tappable.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppConstants.spaceMd),
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppConstants.radiusMd);

    return Container(
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surface.withValues(alpha: 0.65),
        borderRadius: radius,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}
