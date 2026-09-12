import 'package:flutter/material.dart';

/// Visual weight of an [AppButton]. Mirrors the wireframes: a solid blue
/// primary action ("Log In", "Assign Task"), an outlined secondary action
/// ("Continue with Google"), and a solid green action for
/// reward/celebration moments ("Assign Rewards", "Great job!").
enum AppButtonVariant { primary, secondary, success }

/// A single reusable, full-width button used across every feature so
/// buttons look and behave consistently without every screen re-styling
/// `ElevatedButton`/`OutlinedButton` by hand.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = onPressed == null || isLoading;

    final child = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == AppButtonVariant.secondary
                    ? theme.colorScheme.primary
                    : Colors.white,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    late final Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
        button = ElevatedButton(onPressed: isDisabled ? null : onPressed, child: child);
        break;
      case AppButtonVariant.secondary:
        button = OutlinedButton(onPressed: isDisabled ? null : onPressed, child: child);
        break;
      case AppButtonVariant.success:
        button = ElevatedButton(
          onPressed: isDisabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.secondary,
            foregroundColor: Colors.white,
          ),
          child: child,
        );
        break;
    }

    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
