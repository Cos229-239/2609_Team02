import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/auth_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth mockAuth;

  final googleUser = MockUser(uid: 'google-1', email: 'gina@gmail.com', displayName: 'Gina Gee');

  AuthService service({String? idToken = 'fake-id-token'}) => AuthService(
        auth: mockAuth,
        firestore: firestore,
        googleIdTokenProvider: () async => idToken,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(mockUser: googleUser);
  });

  group('Google sign-in', () {
    test('cancelling the account picker does nothing', () async {
      final auth = service(idToken: null);
      expect(await auth.signInWithGoogle(), isNull);
      expect(auth.isLoggedIn, isFalse);
      expect(mockAuth.currentUser, isNull);
    });

    test('a new Google account needs setup, prefilled from the account', () async {
      final auth = service();
      final result = await auth.signInWithGoogle();
      expect(result!.needsSetup, isTrue);
      expect(result.suggestedName, 'Gina Gee');
      expect(result.email, 'gina@gmail.com');
      expect(auth.isLoggedIn, isFalse); // no profile yet
    });

    test('finishing setup as a parent creates their household', () async {
      final auth = service();
      await auth.signInWithGoogle();
      final user = await auth.completeSocialSignUp(name: 'Gina Gee');

      expect(user.id, 'google-1');
      expect(user.email, 'gina@gmail.com');
      expect(user.role, UserRole.parent);
      expect(auth.isLoggedIn, isTrue);
      final household = await firestore.collection('households').doc(user.householdId).get();
      expect(household.data()?['ownerId'], 'google-1');
      final profile = await firestore.collection('users').doc('google-1').get();
      expect(profile.data()?['name'], 'Gina Gee');
    });

    test('finishing setup as a child files a join request', () async {
      await firestore.collection('households').doc('household-1').set({
        'name': 'The Pats',
        'memberIds': ['parent-1'],
        'ownerId': 'parent-1',
        'inviteCode': 'ABC234',
      });
      final auth = service();
      await auth.signInWithGoogle();
      final user = await auth.completeSocialSignUp(name: 'Gina', role: UserRole.child, inviteCode: 'abc234');

      expect(user.householdId, isNull);
      expect(user.pendingHouseholdIds, ['household-1']);
      final request = await firestore
          .collection('households')
          .doc('household-1')
          .collection('joinRequests')
          .doc('google-1')
          .get();
      expect(request.exists, isTrue);
    });

    test('a bad invite code fails without writing a profile, so the user can retry', () async {
      final auth = service();
      await auth.signInWithGoogle();
      await expectLater(
        auth.completeSocialSignUp(name: 'Gina', role: UserRole.child, inviteCode: 'NOPE99'),
        throwsA(isA<Exception>()),
      );
      expect((await firestore.collection('users').doc('google-1').get()).exists, isFalse);
      expect(mockAuth.currentUser, isNotNull);
    });

    test('a returning Google user is signed straight in', () async {
      await firestore.collection('users').doc('google-1').set(const AppUser(
        id: 'google-1',
        name: 'Gina Gee',
        email: 'gina@gmail.com',
        role: UserRole.parent,
        householdId: 'household-1',
      ).toFirestore());

      final auth = service();
      final result = await auth.signInWithGoogle();
      expect(result!.needsSetup, isFalse);
      expect(result.user!.name, 'Gina Gee');
      expect(auth.currentUser?.id, 'google-1');
    });

    test('backing out of setup signs out', () async {
      final auth = service();
      await auth.signInWithGoogle();
      await auth.cancelSocialSignUp();
      expect(mockAuth.currentUser, isNull);
      expect(auth.isLoggedIn, isFalse);
    });
  });
}
