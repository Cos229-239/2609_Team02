import 'dart:math';

import 'package:famotive/shared/widgets/parental_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Same seed for the gate and for the test, so the test knows each answer.
  const seed = 42;
  late Random expected;

  setUp(() {
    ParentalGate.random = Random(seed);
    expected = Random(seed);
  });

  Future<Future<bool>> openGate(WidgetTester tester) async {
    late Future<bool> result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => result = ParentalGate.verify(context),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('parental-gate')), findsOneWidget);
    return result;
  }

  Future<void> answer(WidgetTester tester, int value) async {
    await tester.enterText(find.byKey(const Key('parental-gate-answer')), '$value');
    await tester.tap(find.byKey(const Key('parental-gate-submit')));
    await tester.pumpAndSettle();
  }

  test('questions are word problems with two-digit products', () {
    final r = Random(1);
    for (var i = 0; i < 200; i++) {
      final q = ParentalGateQuestion.next(r);
      expect(q.a, inInclusiveRange(12, 19));
      expect(q.b, inInclusiveRange(3, 9));
      expect(q.prompt, isNot(matches(RegExp(r'\d'))), reason: 'numbers are written in words');
    }
  });

  testWidgets('correct answer passes', (tester) async {
    final result = await openGate(tester);
    final q = ParentalGateQuestion.next(expected);
    expect(find.text(q.prompt), findsOneWidget);
    await answer(tester, q.answer);
    expect(await result, isTrue);
  });

  testWidgets('wrong answer shows a new question, then the right one passes', (tester) async {
    final result = await openGate(tester);
    final first = ParentalGateQuestion.next(expected);
    await answer(tester, first.answer + 1);
    expect(find.byKey(const Key('parental-gate')), findsOneWidget);
    final second = ParentalGateQuestion.next(expected);
    expect(find.text(second.prompt), findsOneWidget);
    await answer(tester, second.answer);
    expect(await result, isTrue);
  });

  testWidgets('closes as failed after ${ParentalGate.maxAttempts} wrong answers', (tester) async {
    final result = await openGate(tester);
    for (var i = 0; i < ParentalGate.maxAttempts; i++) {
      await answer(tester, ParentalGateQuestion.next(expected).answer + 1);
    }
    expect(find.byKey(const Key('parental-gate')), findsNothing);
    expect(await result, isFalse);
  });

  testWidgets('cancel fails', (tester) async {
    final result = await openGate(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
