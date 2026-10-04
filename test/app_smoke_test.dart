import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:famotive/app/app.dart';
import 'package:famotive/core/services/auth_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // These widget tests build the real `FamotiveApp`.
  // Firebase Auth and Firestore are replaced with test doubles so the
  // app can be exercised without connecting to live Firebase services.
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth firebaseAuth;
  late AuthService authService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    firebaseAuth = MockFirebaseAuth();

    authService = AuthService(auth: firebaseAuth, firestore: firestore);
  });

  testWidgets('App starts on the login screen', (tester) async {
    await tester.pumpWidget(
      FamotiveApp(
        authService: authService,
        navigatorKey: GlobalKey<NavigatorState>(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('New to Famotive? '), findsOneWidget);
  });

  testWidgets('Sign Up link navigates to the register screen', (tester) async {
    await tester.pumpWidget(
      FamotiveApp(
        authService: authService,
        navigatorKey: GlobalKey<NavigatorState>(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsWidgets);
  });
}
