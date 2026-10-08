import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_service.dart';

/// "Continue with Google" and (on iPhone/iPad) "Continue with Apple".
///
/// Used on both the login and register screens: the same buttons sign
/// returning users in and start sign-up for new ones, who then land on
/// FinishSignUpScreen to pick a role and household.
class SocialSignInButtons extends StatefulWidget {
  const SocialSignInButtons({super.key});

  /// Apple sign-in is offered on iOS only (where Apple requires it once
  /// Google sign-in exists).
  static bool get appleAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

enum _Provider { google, apple }

class _SocialSignInButtonsState extends State<SocialSignInButtons> {
  _Provider? _busy;

  Future<void> _signIn(_Provider provider) async {
    if (_busy != null) return;
    setState(() => _busy = provider);
    final auth = context.read<AuthService>();
    try {
      final result = provider == _Provider.google
          ? await auth.signInWithGoogle()
          : await auth.signInWithApple();
      if (!mounted || result == null) return; // cancelled
      if (result.needsSetup) {
        await Navigator.of(context).pushNamed(AppRoutes.finishSignUp, arguments: result);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (SocialSignInButtons.appleAvailable) ...[
          _ProviderButton(
            label: 'Continue with Apple',
            icon: const Icon(Icons.apple, size: 24, color: Colors.white),
            background: Colors.black,
            foreground: Colors.white,
            isLoading: _busy == _Provider.apple,
            onPressed: _busy == null ? () => _signIn(_Provider.apple) : null,
          ),
          const SizedBox(height: 12),
        ],
        _ProviderButton(
          label: 'Continue with Google',
          icon: const _GoogleMark(),
          background: Colors.white,
          foreground: Colors.black87,
          border: BorderSide(color: Colors.grey.shade300),
          isLoading: _busy == _Provider.google,
          onPressed: _busy == null ? () => _signIn(_Provider.google) : null,
        ),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.isLoading,
    required this.onPressed,
    this.border,
  });

  final String label;
  final Widget icon;
  final Color background;
  final Color foreground;
  final BorderSide? border;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background,
          disabledForegroundColor: foreground.withValues(alpha: 0.6),
          elevation: 0,
          side: border,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: foreground),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}

/// A simple multi-colour "G" (no image asset needed).
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const SweepGradient(
        colors: [
          Color(0xFFEA4335),
          Color(0xFFFBBC05),
          Color(0xFF34A853),
          Color(0xFF4285F4),
          Color(0xFFEA4335),
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(bounds),
      child: const Text(
        'G',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
      ),
    );
  }
}
