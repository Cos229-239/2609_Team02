import 'dart:math';

import 'package:famotive/shared/widgets/parent_verification.dart';
import 'package:famotive/shared/widgets/parental_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBiometrics implements ParentBiometrics {
  _FakeBiometrics({required this.available, required this.passes});

  final bool available;
  final bool passes;
  final reasons = <String>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    return passes;
  }
}

void main() {
  late ParentBiometrics original;

  setUp(() {
    original = ParentVerification.biometrics;
    ParentalGate.random = Random(7);
  });
  tearDown(() => ParentVerification.biometrics = original);

  Future<Future<bool>> open(WidgetTester tester) async {
    late Future<bool> result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => result = ParentVerification.verify(context, reason: 'Leave Rex', gateReason: 'Grown-ups only'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a successful Face ID / Touch ID scan passes without the math gate', (tester) async {
    final bio = _FakeBiometrics(available: true, passes: true);
    ParentVerification.biometrics = bio;
    final result = await open(tester);
    expect(await result, isTrue);
    expect(bio.reasons, ['Leave Rex']);
    expect(find.byKey(const Key('parental-gate')), findsNothing);
  });

  testWidgets('a failed or cancelled scan falls back to the math gate', (tester) async {
    ParentVerification.biometrics = _FakeBiometrics(available: true, passes: false);
    final result = await open(tester);
    expect(find.byKey(const Key('parental-gate')), findsOneWidget);
    expect(find.text('Grown-ups only'), findsOneWidget);

    final q = ParentalGateQuestion.next(Random(7));
    await tester.enterText(find.byKey(const Key('parental-gate-answer')), '${q.answer}');
    await tester.tap(find.byKey(const Key('parental-gate-submit')));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('no biometrics on the device: straight to the math gate, cancel fails', (tester) async {
    final bio = _FakeBiometrics(available: false, passes: true);
    ParentVerification.biometrics = bio;
    final result = await open(tester);
    expect(bio.reasons, isEmpty);
    expect(find.byKey(const Key('parental-gate')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
