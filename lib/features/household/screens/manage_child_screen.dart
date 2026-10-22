import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_notice.dart';
import '../widgets/add_child_sheet.dart' show childAvatarChoices;
import '../widgets/child_account_actions.dart';

/// Parent: everything about one child's account in one place - name, age,
/// avatar, login email, a new password, and deleting the account - so a
/// parent never has to leave the app (or sign in as the child) to fix it.
/// Also removes the child from the household (any parent) or deletes the
/// account (admin).
///
/// Name/age/avatar are saved straight to the child's profile. Email and
/// password go through the `manageChildAccount` Cloud Function, and
/// deleting through `deleteAccount`; all three ask for the parent's own
/// password first.
class ManageChildScreen extends StatelessWidget {
  const ManageChildScreen({super.key, required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final child = db.userById(childId);
    final me = context.watch<AuthService>().currentUser;
    final isAdmin = db.household?.isAdmin(me?.id) ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(child == null ? 'Child account' : "${child.name}'s account")),
      body: child == null || !child.isChild
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text("This child isn't in your household any more.", textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _ProfileSection(key: ValueKey('profile-${child.id}'), child: child),
                const SizedBox(height: 16),
                _EmailSection(key: ValueKey('email-${child.id}'), child: child),
                const SizedBox(height: 16),
                _PasswordSection(child: child),
                const SizedBox(height: 28),
                _DangerZone(child: child, canDelete: isAdmin),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _message(Object e) => e.toString().replaceFirst('Exception: ', '');

// --- Name, age, avatar ----------------------------------------------------

class _ProfileSection extends StatefulWidget {
  const _ProfileSection({super.key, required this.child});

  final AppUser child;

  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.child.name);
  late final _age = TextEditingController(text: widget.child.age?.toString() ?? '');
  late String _avatar = widget.child.avatarEmoji;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  List<String> get _choices => [
        if (!childAvatarChoices.contains(widget.child.avatarEmoji)) widget.child.avatarEmoji,
        ...childAvatarChoices,
      ];

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ageText = _age.text.trim();
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().updateChildProfile(
            childId: widget.child.id,
            name: _name.text,
            avatarEmoji: _avatar,
            age: ageText.isEmpty ? null : int.parse(ageText),
          );
      if (mounted) showAppNotice(context, 'Saved ${_name.text.trim()}\'s profile.', tone: NoticeTone.success);
    } catch (e) {
      if (mounted) showAppNotice(context, _message(e), tone: NoticeTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(Icons.face_retouching_natural, 'Profile', 'Name, age and avatar your child sees.'),
            Center(
              child: CircleAvatar(
                radius: 34,
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                child: Text(_avatar, style: const TextStyle(fontSize: 34)),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final a in _choices)
                  ChoiceChip(
                    key: Key('avatar-$a'),
                    label: Text(a, style: const TextStyle(fontSize: 20)),
                    selected: _avatar == a,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _avatar = a),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('child-name-field'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: "Child's name *"),
              validator: (v) => Validators.required(v, fieldName: "child's name"),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const Key('child-age-field'),
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
            const SizedBox(height: 14),
            AppButton(
              key: const Key('save-child-profile'),
              label: 'Save Profile',
              icon: Icons.check,
              isLoading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Login email ------------------------------------------------------------

class _EmailSection extends StatefulWidget {
  const _EmailSection({super.key, required this.child});

  final AppUser child;

  @override
  State<_EmailSection> createState() => _EmailSectionState();
}

class _EmailSectionState extends State<_EmailSection> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.child.email);
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    if (email.toLowerCase() == widget.child.email.toLowerCase()) {
      showAppNotice(context, "That's already ${widget.child.name}'s login email.");
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await confirmParentIdentity(context,
          message: "Enter your password to change ${widget.child.name}'s login email.")) {
        return;
      }
      if (!mounted) return;
      final saved = await context.read<AuthService>().updateChildEmail(widget.child.id, email);
      if (!mounted) return;
      _email.text = saved;
      showAppNotice(context, '${widget.child.name} now logs in with $saved.', tone: NoticeTone.success);
    } catch (e) {
      if (mounted) showAppNotice(context, _message(e), tone: NoticeTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(Icons.alternate_email, 'Login email', 'The email your child signs in with.'),
            TextFormField(
              key: const Key('child-email-field'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Login email *'),
              validator: Validators.email,
            ),
            const SizedBox(height: 14),
            AppButton(
              key: const Key('save-child-email'),
              label: 'Change Email',
              icon: Icons.mark_email_read_outlined,
              variant: AppButtonVariant.secondary,
              isLoading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// --- New password ---------------------------------------------------------

class _PasswordSection extends StatefulWidget {
  const _PasswordSection({required this.child});

  final AppUser child;

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (!await confirmParentIdentity(context,
          message: "Enter YOUR password to set a new one for ${widget.child.name}.")) {
        return;
      }
      if (!mounted) return;
      await context.read<AuthService>().setChildPassword(widget.child.id, _password.text);
      if (!mounted) return;
      _password.clear();
      _confirm.clear();
      showAppNotice(
        context,
        "${widget.child.name}'s password was changed. They'll need the new one to log in.",
        tone: NoticeTone.success,
      );
    } catch (e) {
      if (mounted) showAppNotice(context, _message(e), tone: NoticeTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      tooltip: _obscure ? 'Show password' : 'Hide password',
      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _obscure = !_obscure),
    );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(
              Icons.lock_reset,
              'Reset password',
              "Forgot it? Set a new one here - no email needed. ${widget.child.name} is signed out on other devices.",
            ),
            TextFormField(
              key: const Key('child-password-field'),
              controller: _password,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: 'New password *', suffixIcon: toggle),
              validator: Validators.password,
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const Key('child-password-confirm-field'),
              controller: _confirm,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Confirm new password *'),
              validator: Validators.confirmPassword(() => _password.text),
            ),
            const SizedBox(height: 14),
            AppButton(
              key: const Key('save-child-password'),
              label: 'Set New Password',
              icon: Icons.key,
              variant: AppButtonVariant.secondary,
              isLoading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Remove / delete ------------------------------------------------------

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.child, required this.canDelete});

  final AppUser child;

  /// Only the household's admin may delete a child's account.
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = OutlinedButton.styleFrom(
      foregroundColor: Colors.red.shade700,
      side: BorderSide(color: Colors.red.shade300),
      padding: const EdgeInsets.symmetric(vertical: 14),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Danger zone', style: theme.textTheme.titleSmall?.copyWith(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          "Removing ${child.name} means their account is no longer managed by this household's parents.",
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('remove-child-from-household'),
          style: style,
          icon: const Icon(Icons.person_remove_outlined),
          label: const Text('Remove from household'),
          onPressed: () async {
            final navigator = Navigator.of(context);
            if (await confirmRemoveChildFromHousehold(context, child)) navigator.maybePop();
          },
        ),
        if (canDelete) ...[
          const SizedBox(height: 16),
          Text(
            "Deleting removes ${child.name}'s login, XP, coins, tasks and reward history for good.",
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('delete-child-account'),
            style: style,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text("Delete ${child.name}'s account"),
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (await confirmDeleteChildAccount(context, child)) navigator.maybePop();
            },
          ),
        ],
      ],
    );
  }
}
