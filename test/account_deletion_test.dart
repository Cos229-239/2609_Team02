import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/services/auth_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth mockAuth;
  late List<Map<String, dynamic>> calls;
  late Map<String, dynamic> response;

  AuthService service() => AuthService(
        auth: mockAuth,
        firestore: firestore,
        accountDeletionCall: (data) async {
          calls.add(data);
          return response;
        },
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth();
    calls = [];
    response = {'deleted': true};
  });

  test('preview asks for a dry run and parses the result', () async {
    response = {
      'forbidden': null,
      'blockers': ['Make another parent the admin of Home first.'],
      'deletedHouseholds': <String>[],
      'leftHouseholds': ['Grandma'],
      'deletedAccounts': <String>[],
    };
    final auth = service();
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');

    final preview = await auth.previewAccountDeletion();
    expect(calls.single, {'dryRun': true});
    expect(preview.canDelete, isFalse);
    expect(preview.blockers.single, contains('admin'));
    expect(preview.leftHouseholds, ['Grandma']);
  });

  test('child preview passes the child id', () async {
    response = {'blockers': <String>[], 'deletedAccounts': <String>[]};
    final auth = service();
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');

    final preview = await auth.previewAccountDeletion(childId: 'kid-1');
    expect(calls.single, {'dryRun': true, 'childId': 'kid-1'});
    expect(preview.canDelete, isTrue);
  });

  test('deleting the account signs out and runs logout hooks', () async {
    final auth = service();
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');
    var hookRan = false;
    auth.addBeforeLogoutHook(() async => hookRan = true);

    await auth.deleteAccount();
    expect(calls.single, isEmpty);
    expect(hookRan, isTrue);
    expect(auth.isLoggedIn, isFalse);
    expect(mockAuth.currentUser, isNull);
  });

  test('a failed deletion keeps the user signed in', () async {
    final auth = AuthService(
      auth: mockAuth,
      firestore: firestore,
      accountDeletionCall: (_) async => throw Exception('Make another parent the admin of Home first.'),
    );
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');

    await expectLater(auth.deleteAccount(), throwsA(isA<Exception>()));
    expect(auth.isLoggedIn, isTrue);
  });

  test('a parent deletes a child account by id', () async {
    final auth = service();
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');
    await auth.deleteChildAccount('kid-1');
    expect(calls.single, {'childId': 'kid-1'});
    expect(auth.isLoggedIn, isTrue);
  });
}
