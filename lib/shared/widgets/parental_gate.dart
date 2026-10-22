import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Parental gate required by App Store guideline 1.3 (Kids Category) and
/// Google Play's Families policy: an adult must pass it before the app
/// leaves to another app or website (Terms, Privacy Policy, mail app for
/// support, store subscription settings) or starts a purchase.
///
/// The question is a two-digit × one-digit multiplication written out in
/// words ("What is fourteen times six?"), answered with digits: easy for a
/// parent, hard for a young child to read and solve. Every attempt gets a
/// new question, and after [maxAttempts] wrong answers the gate closes.
///
/// There is deliberately no setting, flag or "remember me" that turns the
/// gate off: Apple requires that it can't be disabled.
///
/// ```dart
/// if (!await ParentalGate.verify(context)) return;
/// await launchUrl(uri);
/// ```
class ParentalGate {
  ParentalGate._();

  static const int maxAttempts = 3;

  /// Source of the questions. Tests swap in a seeded [Random] to know the
  /// answers; it never skips the gate.
  @visibleForTesting
  static Random random = Random.secure();

  static const String defaultReason =
      'This leaves Famotive or involves a purchase. A parent needs to answer to continue.';

  /// Shows the gate. Resolves to true only when a correct answer was given.
  /// [reason] replaces the line explaining why a grown-up is needed.
  static Future<bool> verify(BuildContext context, {String reason = defaultReason}) async {
    final passed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _ParentalGateDialog(reason: reason),
    );
    return passed ?? false;
  }
}

/// One gate question: [a] × [b], with [a] in 12–19 and [b] in 3–9.
class ParentalGateQuestion {
  ParentalGateQuestion(this.a, this.b);

  factory ParentalGateQuestion.next([Random? random]) {
    final r = random ?? ParentalGate.random;
    return ParentalGateQuestion(12 + r.nextInt(8), 3 + r.nextInt(7));
  }

  final int a;
  final int b;

  int get answer => a * b;

  String get prompt => 'What is ${_words[a]} times ${_words[b]}?';

  static const _words = {
    3: 'three', 4: 'four', 5: 'five', 6: 'six', 7: 'seven', 8: 'eight', 9: 'nine',
    12: 'twelve', 13: 'thirteen', 14: 'fourteen', 15: 'fifteen',
    16: 'sixteen', 17: 'seventeen', 18: 'eighteen', 19: 'nineteen',
  };
}

class _ParentalGateDialog extends StatefulWidget {
  const _ParentalGateDialog({required this.reason});

  final String reason;

  @override
  State<_ParentalGateDialog> createState() => _ParentalGateDialogState();
}

class _ParentalGateDialogState extends State<_ParentalGateDialog> {
  final _controller = TextEditingController();
  late ParentalGateQuestion _question = ParentalGateQuestion.next();
  int _wrong = 0;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (int.tryParse(_controller.text.trim()) == _question.answer) {
      Navigator.of(context).pop(true);
      return;
    }
    _wrong++;
    if (_wrong >= ParentalGate.maxAttempts) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _question = ParentalGateQuestion.next();
      _controller.clear();
      _error = "That's not right. Here's a new one.";
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('parental-gate'),
      title: const Text('Ask a Grown-Up'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.reason, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Text(
            _question.prompt,
            key: const Key('parental-gate-question'),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('parental-gate-answer'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Answer in numbers',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          key: const Key('parental-gate-submit'),
          onPressed: _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
