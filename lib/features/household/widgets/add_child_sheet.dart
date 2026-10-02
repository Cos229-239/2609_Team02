import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';

const _avatarChoices = ['🧒', '👧', '👦', '🧒🏽', '👧🏾', '👦🏻', '🦄', '🐯', '🐼', '🚀'];

/// Lets a parent create a login for a child right from the Family tab.
/// The email is pre-filled as the parent's own address plus a "+name" tag
/// (e.g. mom+ava@example.com) since many kids don't have one; it's editable.
/// The child joins the active household immediately - no approval needed.
Future<void> showAddChildSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AddChildSheet(),
  );
}

class _AddChildSheet extends StatefulWidget {
  const _AddChildSheet();

  @override
  State<_AddChildSheet> createState() => _AddChildSheetState();
}

class _AddChildSheetState extends State<_AddChildSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _avatar = _avatarChoices.first;

  /// Stops auto-filling once the parent types their own email.
  bool _emailEdited = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_autofillEmail);
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _autofillEmail() {
    if (_emailEdited) return;
    final parentEmail = context.read<AuthService>().currentUser?.email ?? '';
    final suggestion = AuthService.suggestChildEmail(parentEmail, _name.text);
    if (_email.text != suggestion) _email.text = suggestion;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final householdId = context.read<DatabaseService>().household?.id;
    if (householdId == null) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().createChildAccount(
            householdId: householdId,
            name: _name.text,
            email: _email.text,
            password: _password.text,
            age: int.tryParse(_age.text.trim()),
            avatarEmoji: _avatar,
          );
      if (!mounted) return;
      final name = _name.text.trim();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('$name was added! They can log in with ${_email.text.trim()}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add a Child', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Creates a login for your child and adds them to this household. '
                'XP and coins they earn stay with their account in every household.',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in _avatarChoices)
                    ChoiceChip(
                      label: Text(a, style: const TextStyle(fontSize: 20)),
                      selected: _avatar == a,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _avatar = a),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: "Child's name *"),
                validator: (v) => Validators.required(v, fieldName: "child's name"),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _age,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age (optional)'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  final n = int.tryParse(t);
                  return n == null || n < 1 || n > 17 ? 'Enter an age from 1 to 17' : null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Login email *',
                  helperText: 'Your email + their name. Resets come to your inbox.',
                ),
                onChanged: (_) => _emailEdited = true,
                validator: Validators.email,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password *'),
                validator: Validators.password,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password *'),
                validator: Validators.confirmPassword(() => _password.text),
              ),
              const SizedBox(height: 18),
              AppButton(
                label: 'Create Child Account',
                icon: Icons.person_add_alt_1,
                isLoading: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
