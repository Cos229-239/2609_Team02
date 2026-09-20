import 'package:flutter/material.dart';

import '../../../core/utils/validators.dart';
import '../../auth/widgets/auth_text_field.dart';

/// Small dialog that asks for the signed-in user's current password
/// before a sensitive change (like an email update) that Firebase Auth
/// requires a "recent login" for. Returns the entered password, or null
/// if the user cancelled.
class CurrentPasswordPrompt extends StatefulWidget {
  const CurrentPasswordPrompt({super.key, required this.message});

  final String message;

  static Future<String?> show(BuildContext context, {required String message}) {
    return showDialog<String>(
      context: context,
      builder: (context) => CurrentPasswordPrompt(message: message),
    );
  }

  @override
  State<CurrentPasswordPrompt> createState() => _CurrentPasswordPromptState();
}

class _CurrentPasswordPromptState extends State<CurrentPasswordPrompt> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Your Password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            AuthTextField(
              controller: _passwordController,
              label: 'Current Password',
              icon: Icons.lock_outline,
              obscureText: true,
              textInputAction: TextInputAction.done,
              validator: (v) => Validators.required(v, fieldName: 'current password'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
