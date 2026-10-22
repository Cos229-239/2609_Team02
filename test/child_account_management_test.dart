import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/auth_service.dart';

/// A parent managing a child's account from inside the app
/// (ManageChildScreen): profile fields go straight to Firestore, login
/// changes through the `manageChildAccount` Cloud Function.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late List<Map<String, dynamic>> calls;
  late Map<String, dynamic> response;

  AuthService service() => AuthService(
        auth: MockFirebaseAuth(),
        firestore: firestore,
        childLoginCall: (data) async {
          calls.add(data);
          return response;
        },
      );

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    calls = [];
    response = {'ok': true};
    await firestore.collection('users').doc('kid-1').set({
      'name': 'Ava',
      'email': 'pat+ava@example.com',
      'role': 'child',
      'avatarEmoji': '🧒',
      'age': 7,
      'xp': 40,
      'coins': 3,
    });
  });

  test('parent edits name, age and avatar without touching balances', () async {
    final auth = service();
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');

    await auth.updateChildProfile(childId: 'kid-1', name: '  Ava Rose ', avatarEmoji: '🦄', age: 8);
    final kid = (await firestore.collection('users').doc('kid-1').get()).data()!;
    expect(kid['name'], 'Ava Rose');
    expect(kid['avatarEmoji'], '🦄');
    expect(kid['age'], 8);
    expect(kid['xp'], 40);
    expect(kid['coins'], 3);

    await auth.updateChildProfile(childId: 'kid-1', name: 'Ava', avatarEmoji: '🦄');
    expect((await firestore.collection('users').doc('kid-1').get()).data()!['age'], isNull);
  });

  test('an empty name is refused', () async {
    final auth = service();
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');
    await expectLater(
      auth.updateChildProfile(childId: 'kid-1', name: '  ', avatarEmoji: '🦄'),
      throwsA(isA<Exception>()),
    );
  });

  test('password reset calls the server with the child id', () async {
    final auth = service();
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');
    await auth.setChildPassword('kid-1', 'newpass1');
    expect(calls.single, {'childId': 'kid-1', 'password': 'newpass1'});
  });

  test('email change returns what the server saved', () async {
    response = {'ok': true, 'email': 'ava@example.com'};
    final auth = service();
    await auth.register(name: 'Pat', email: 'pat@example.com', password: 'secret1');
    final saved = await auth.updateChildEmail('kid-1', '  Ava@Example.com ');
    expect(calls.single, {'childId': 'kid-1', 'email': 'Ava@Example.com'});
    expect(saved, 'ava@example.com');
  });

  test('a child cannot manage another child', () async {
    final parent = await service().register(name: 'Pat', email: 'pat@example.com', password: 'secret1');
    final household = await firestore.collection('households').doc(parent.householdId).get();
    final auth = service();
    await auth.register(
      name: 'Ben',
      email: 'ben@example.com',
      password: 'secret1',
      role: UserRole.child,
      inviteCode: household.data()!['inviteCode'] as String,
    );
    await expectLater(auth.setChildPassword('kid-1', 'newpass1'), throwsA(isA<Exception>()));
    await expectLater(auth.updateChildEmail('kid-1', 'x@example.com'), throwsA(isA<Exception>()));
    await expectLater(
      auth.updateChildProfile(childId: 'kid-1', name: 'X', avatarEmoji: '🦄'),
      throwsA(isA<Exception>()),
    );
    expect(calls, isEmpty);
  });

  test("a child can change their avatar but not their own name, age, email or password", () async {
    final parent = await service().register(name: 'Pat', email: 'pat@example.com', password: 'secret1');
    final household = await firestore.collection('households').doc(parent.householdId).get();
    final auth = service();
    final kid = await auth.register(
      name: 'Ben',
      email: 'ben@example.com',
      password: 'secret1',
      role: UserRole.child,
      inviteCode: household.data()!['inviteCode'] as String,
    );

    await auth.updateProfile(name: 'Benjamin the Great', avatarEmoji: '🚀', age: 16);
    final saved = (await firestore.collection('users').doc(kid.id).get()).data()!;
    expect(saved['name'], 'Ben');
    expect(saved['age'], isNull);
    expect(saved['avatarEmoji'], '🚀');

    await expectLater(
      auth.updatePassword(currentPassword: 'secret1', newPassword: 'hacked1'),
      throwsA(predicate((e) => '$e'.contains('Ask a parent'))),
    );
    await expectLater(
      auth.updateEmail(newEmail: 'ben2@example.com', currentPassword: 'secret1'),
      throwsA(predicate((e) => '$e'.contains('Ask a parent'))),
    );
  });
}
