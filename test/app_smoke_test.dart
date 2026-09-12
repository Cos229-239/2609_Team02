import 'package:famotive/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App starts on the login screen', (tester) async {
    await tester.pumpWidget(const FamotiveApp());
    await tester.pumpAndSettle();

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('New to Famotive? '), findsOneWidget);
  });

  testWidgets('Sign Up link navigates to the register screen', (tester) async {
    await tester.pumpWidget(const FamotiveApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsWidgets);
  });
}
