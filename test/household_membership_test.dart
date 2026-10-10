import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/join_request.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/auth_service.dart';
import 'package:famotive/core/services/database_service.dart';

void main() {
  const householdId = 'household-1';
  const parent = AppUser(
    id: 'parent-1',
    name: 'Pat',
    email: 'pat@example.com',
    role: UserRole.parent,
    householdId: householdId,
  );
  const child = AppUser(
    id: 'child-1',
    name: 'Ava',
    email: 'pat+ava@example.com',
    role: UserRole.child,
    householdId: householdId,
  );

  late FakeFirebaseFirestore firestore;
  late DatabaseService db;

  CollectionReference<Map<String, dynamic>> tasks() =>
      firestore.collection('households').doc(householdId).collection('tasks');

  Future<void> seedHousehold({
    List<String> memberIds = const ['parent-1', 'child-1'],
    String? ownerId = 'parent-1',
  }) async {
    await firestore.collection('households').doc(householdId).set({
      'name': 'The Pats',
      'memberIds': memberIds,
      'ownerId': ownerId,
      'inviteCode': 'ABC234',
      'timezone': 'America/Denver',
    });
    await firestore
        .collection('users')
        .doc(parent.id)
        .set(parent.toFirestore());
    await firestore.collection('users').doc(child.id).set(child.toFirestore());
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    db = DatabaseService(
      firestore: firestore,
      deviceTimeZone: () async => null,
    );
  });

  group('suggestChildEmail', () {
    test("uses the parent's address with a +name tag", () {
      expect(
        AuthService.suggestChildEmail('pat@example.com', 'Ava'),
        'pat+ava@example.com',
      );
      expect(
        AuthService.suggestChildEmail('pat@example.com', 'Mary Jo'),
        'pat+maryjo@example.com',
      );
    });

    test("replaces an existing tag and handles blanks", () {
      expect(
        AuthService.suggestChildEmail('pat+work@example.com', 'Leo'),
        'pat+leo@example.com',
      );
      expect(AuthService.suggestChildEmail('pat@example.com', '  '), '');
      expect(AuthService.suggestChildEmail('not-an-email', 'Leo'), '');
    });
  });

  group('memberships', () {
    test(
      'lists my households and the active household members in order',
      () async {
        await seedHousehold();
        await firestore.collection('households').doc('household-2').set({
          'name': 'Grandparents House',
          'memberIds': ['child-1'],
          'ownerId': 'grandma',
        });

        db.bindSession(child);
        await pumpEventQueue();

        expect(db.myHouseholds.map((h) => h.name), ['Grandparents House', 'The Pats']);
        expect(db.familyMembers.map((m) => m.id), ['parent-1', 'child-1']);
        expect(db.household?.isAdmin('parent-1'), isTrue);
      },
    );

    test(
      'switching households updates members and switching back restores them',
      () async {
        await seedHousehold();

        await firestore.collection('households').doc('household-2').set({
          'name': 'Grandma',
          'memberIds': ['parent-1'],
          'ownerId': 'parent-1',
          'inviteCode': 'GRAND1',
          'timezone': 'America/Denver',
        });

        db.bindSession(parent);
        await pumpEventQueue();

        // The parent's original household contains both parent and child.
        expect(db.household?.id, householdId);
        expect(db.familyMembers.map((m) => m.id), ['parent-1', 'child-1']);

        // Switching to the second household should remove the first
        // household's child from the active member list.
        db.bindHousehold('household-2');
        await pumpEventQueue();

        expect(db.household?.id, 'household-2');
        expect(db.familyMembers.map((m) => m.id), ['parent-1']);
        expect(db.familyMembers.map((m) => m.id), isNot(contains('child-1')));

        // Switching back should restore the original household's members.
        db.bindHousehold(householdId);
        await pumpEventQueue();

        expect(db.household?.id, householdId);
        expect(db.familyMembers.map((m) => m.id), ['parent-1', 'child-1']);
      },
    );

    test(
      'switching households keeps tasks isolated to the active household',
      () async {
        await seedHousehold();

        await firestore.collection('households').doc('household-2').set({
          'name': 'Grandma',
          'memberIds': ['parent-1'],
          'ownerId': 'parent-1',
          'inviteCode': 'GRAND1',
          'timezone': 'America/Denver',
        });

        await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .doc('family-task')
            .set(
              const TaskModel(
                id: 'family-task',
                title: 'Family dishes',
              ).toFirestore(),
            );

        await firestore
            .collection('households')
            .doc('household-2')
            .collection('tasks')
            .doc('grandma-task')
            .set(
              const TaskModel(
                id: 'grandma-task',
                title: 'Grandma dishes',
              ).toFirestore(),
            );

        db.bindSession(parent);
        await pumpEventQueue();

        expect(db.tasks.map((t) => t.id), ['family-task']);

        db.bindHousehold('household-2');
        await pumpEventQueue();

        expect(db.tasks.map((t) => t.id), ['grandma-task']);
        expect(db.tasks.map((t) => t.id), isNot(contains('family-task')));

        db.bindHousehold(householdId);
        await pumpEventQueue();

        expect(db.tasks.map((t) => t.id), ['family-task']);
        expect(db.tasks.map((t) => t.id), isNot(contains('grandma-task')));
      },
    );

    test('switching households preserves user XP and coins', () async {
      const parentWithProgress = AppUser(
        id: 'parent-1',
        name: 'Pat',
        email: 'pat@example.com',
        role: UserRole.parent,
        householdId: householdId,
        xp: 570,
        coins: 100,
      );

      await seedHousehold();

      // Store the progression values on the user profile.
      await firestore
          .collection('users')
          .doc(parentWithProgress.id)
          .set(parentWithProgress.toFirestore());

      await firestore.collection('households').doc('household-2').set({
        'name': 'Grandma',
        'memberIds': ['parent-1'],
        'ownerId': 'parent-1',
        'inviteCode': 'GRAND1',
        'timezone': 'America/Denver',
      });

      db.bindSession(parentWithProgress);
      await pumpEventQueue();

      var userSnapshot = await firestore
          .collection('users')
          .doc(parentWithProgress.id)
          .get();

      expect(userSnapshot.data()?['xp'], 570);
      expect(userSnapshot.data()?['coins'], 100);

      // Change the active household.
      db.bindHousehold('household-2');
      await pumpEventQueue();

      userSnapshot = await firestore
          .collection('users')
          .doc(parentWithProgress.id)
          .get();

      expect(userSnapshot.data()?['xp'], 570);
      expect(userSnapshot.data()?['coins'], 100);

      // Switching back must not affect account-level progression either.
      db.bindHousehold(householdId);
      await pumpEventQueue();

      userSnapshot = await firestore
          .collection('users')
          .doc(parentWithProgress.id)
          .get();

      expect(userSnapshot.data()?['xp'], 570);
      expect(userSnapshot.data()?['coins'], 100);
    });
    test(
      'asks to switch away when removed from the active household',
      () async {
        await seedHousehold();
        await firestore.collection('households').doc('household-2').set({
          'name': 'Grandma',
          'memberIds': ['child-1'],
        });
        String? switchedTo = 'unset';
        db.onActiveHouseholdMissing = (id) => switchedTo = id;

        db.bindSession(child);
        await pumpEventQueue();
        expect(switchedTo, 'unset');

        await firestore.collection('households').doc(householdId).update({
          'memberIds': FieldValue.arrayRemove(['child-1']),
        });
        await pumpEventQueue();
        expect(switchedTo, 'household-2');
      },
    );

    test(
      'admin approves a join request: member added, request removed',
      () async {
        await seedHousehold(memberIds: ['parent-1']);
        final request = JoinRequest(
          userId: 'child-1',
          householdId: householdId,
          name: 'Ava',
          email: 'ava@example.com',
          role: UserRole.child,
          requestedAt: DateTime(2026, 10, 1),
        );
        await firestore
            .collection('households')
            .doc(householdId)
            .collection('joinRequests')
            .doc('child-1')
            .set(request.toFirestore());

        db.bindSession(parent);
        await pumpEventQueue();
        expect(db.isAdmin, isTrue);
        expect(db.joinRequests.single.name, 'Ava');

        await db.approveJoinRequest(db.joinRequests.single);
        await pumpEventQueue();

        final household = await firestore
            .collection('households')
            .doc(householdId)
            .get();
        expect(household.data()?['memberIds'], ['parent-1', 'child-1']);
        expect(db.joinRequests, isEmpty);
        expect(db.familyMembers.map((m) => m.id), contains('child-1'));
      },
    );

    test(
      'pending request resolves as approved once the user is a member',
      () async {
        await seedHousehold(memberIds: ['parent-1']);
        final waiting = child.copyWith(
          clearHouseholdId: true,
          pendingHouseholdIds: [householdId],
        );
        await firestore
            .collection('households')
            .doc(householdId)
            .collection('joinRequests')
            .doc('child-1')
            .set({
              'userId': 'child-1',
              'householdId': householdId,
              'name': 'Ava',
            });
        final resolved = <String, bool>{};
        db.onPendingRequestResolved = (id, {required approved}) =>
            resolved[id] = approved;

        db.bindSession(waiting);
        await pumpEventQueue();
        expect(resolved, isEmpty);

        await firestore.collection('households').doc(householdId).update({
          'memberIds': FieldValue.arrayUnion(['child-1']),
        });
        await pumpEventQueue();
        expect(resolved, {householdId: true});
      },
    );

    test(
      'removing a child sends their unfinished tasks back to the pool',
      () async {
        await seedHousehold();
        await tasks()
            .doc('t1')
            .set(
              const TaskModel(
                id: 't1',
                title: 'Dishes',
                assignedToUserId: 'child-1',
                status: TaskStatus.completed,
              ).toFirestore(),
            );
        await tasks()
            .doc('t2')
            .set(
              const TaskModel(
                id: 't2',
                title: 'Old win',
                assignedToUserId: 'child-1',
                status: TaskStatus.approved,
              ).toFirestore(),
            );

        db.bindSession(parent);
        await pumpEventQueue();
        await db.removeMember('child-1');
        await pumpEventQueue();

        final t1 = (await tasks().doc('t1').get()).data()!;
        expect(t1['assignedToUserId'], isNull);
        expect(t1['status'], 'pending');
        expect(
          (await tasks().doc('t2').get()).data()!['assignedToUserId'],
          'child-1',
        );
        final household = await firestore
            .collection('households')
            .doc(householdId)
            .get();
        expect(household.data()?['memberIds'], ['parent-1']);
      },
    );

    test("the admin can't be removed", () async {
      await seedHousehold();
      db.bindSession(parent);
      await pumpEventQueue();
      await expectLater(db.removeMember('parent-1'), throwsException);
    });

    test(
      'households without an admin get their first member as admin',
      () async {
        await seedHousehold(ownerId: null);
        db.bindSession(parent);
        await pumpEventQueue();
        final household = await firestore
            .collection('households')
            .doc(householdId)
            .get();
        expect(household.data()?['ownerId'], 'parent-1');
      },
    );
  });

  group('task reassignment (regression)', () {
    setUp(() => db.bindHousehold(householdId));

    test(
      'moving a completed task back to the household resets it to "to do"',
      () async {
        await tasks().doc('t1').set({
          ...const TaskModel(
            id: 't1',
            title: 'Dishes',
            assignedToUserId: 'child-1',
            status: TaskStatus.completed,
          ).toFirestore(),
          'claimedBy': 'child-1',
        });

        await db.reassignTask('t1', null);
        var data = (await tasks().doc('t1').get()).data()!;
        expect(data['status'], 'pending');
        expect(data['assignedToUserId'], isNull);
        expect(data.containsKey('claimedBy'), isFalse);

        // Another child claims it: a fresh to-do, not "awaiting approval".
        await db.claimTask('t1', 'child-2');
        data = (await tasks().doc('t1').get()).data()!;
        expect(data['status'], 'pending');
        expect(data['assignedToUserId'], 'child-2');
      },
    );

    test('editing a task to a different assignee also resets it', () async {
      await tasks()
          .doc('t1')
          .set(
            const TaskModel(
              id: 't1',
              title: 'Dishes',
              assignedToUserId: 'child-1',
              status: TaskStatus.completed,
            ).toFirestore(),
          );
      final saved = TaskModel.fromFirestore(await tasks().doc('t1').get());

      await db.updateTask(
        't1',
        saved.copyWith(clearAssignedToUserId: true, title: 'Dishes!'),
      );
      final data = (await tasks().doc('t1').get()).data()!;
      expect(data['title'], 'Dishes!');
      expect(data['status'], 'pending');
    });

    test('editing without changing the assignee keeps the status', () async {
      await tasks()
          .doc('t1')
          .set(
            const TaskModel(
              id: 't1',
              title: 'Dishes',
              assignedToUserId: 'child-1',
              status: TaskStatus.completed,
            ).toFirestore(),
          );
      final saved = TaskModel.fromFirestore(await tasks().doc('t1').get());

      await db.updateTask('t1', saved.copyWith(title: 'Dishes!'));
      expect((await tasks().doc('t1').get()).data()!['status'], 'completed');
    });
  });

  group('task visibility', () {
    test('approved tasks drop out of lists after 7 days', () {
      final now = DateTime.now();
      db.tasks = [
        TaskModel(
          id: 'recent',
          title: 'a',
          status: TaskStatus.approved,
          approvedAt: now.subtract(const Duration(days: 2)),
        ),
        TaskModel(
          id: 'old',
          title: 'b',
          status: TaskStatus.approved,
          approvedAt: now.subtract(const Duration(days: 8)),
        ),
        TaskModel(
          id: 'pending',
          title: 'c',
          createdAt: now.subtract(const Duration(days: 30)),
        ),
        TaskModel(
          id: 'expired',
          title: 'd',
          createdAt: now.subtract(const Duration(days: 61)),
        ),
      ];
      expect(db.activeTasks.map((t) => t.id), ['recent', 'pending']);
      expect(db.archivedTasks, isEmpty);
    });

    test('completing and approving record timestamps', () async {
      db.bindHousehold(householdId);
      await tasks()
          .doc('t1')
          .set(const TaskModel(id: 't1', title: 'Dishes').toFirestore());
      await db.completeTask('t1');
      expect(
        (await tasks().doc('t1').get()).data()!['completedAt'],
        isA<Timestamp>(),
      );
      await db.approveTask('t1');
      expect(
        (await tasks().doc('t1').get()).data()!['approvedAt'],
        isA<Timestamp>(),
      );
    });
  });

  group('AuthService', () {
    test('a parent signing up becomes admin of their new household', () async {
      final auth = AuthService(auth: MockFirebaseAuth(), firestore: firestore);
      final user = await auth.register(
        name: 'Pat',
        email: 'pat@example.com',
        password: 'secret1',
      );
      final household = await firestore
          .collection('households')
          .doc(user.householdId)
          .get();
      expect(household.data()?['ownerId'], user.id);
      expect(household.data()?['memberIds'], [user.id]);
    });

    test(
      'signing up with an invite code files a join request instead of joining',
      () async {
        await seedHousehold(memberIds: ['parent-1']);
        final auth = AuthService(
          auth: MockFirebaseAuth(),
          firestore: firestore,
        );
        final user = await auth.register(
          name: 'Ava',
          email: 'ava@example.com',
          password: 'secret1',
          role: UserRole.child,
          inviteCode: 'abc234',
        );
        expect(user.householdId, isNull);
        expect(user.pendingHouseholdIds, [householdId]);
        final household = await firestore
            .collection('households')
            .doc(householdId)
            .get();
        expect(household.data()?['memberIds'], ['parent-1']);
        final request = await firestore
            .collection('households')
            .doc(householdId)
            .collection('joinRequests')
            .doc(user.id)
            .get();
        expect(request.data()?['name'], 'Ava');
      },
    );

    test('a parent creates a child account that joins right away', () async {
      await seedHousehold(memberIds: ['parent-1']);
      final mockAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'parent-1', email: 'pat@example.com'),
        signedIn: true,
      );
      Map<String, dynamic>? createdProfile;
      final auth = AuthService(
        auth: mockAuth,
        firestore: firestore,
        childAccountCreator:
            ({required email, required password, required profile}) async {
              createdProfile = profile;
              await firestore.collection('users').doc('new-kid').set(profile);
              return 'new-kid';
            },
      );
      await auth.tryRestoreSession();

      final uid = await auth.createChildAccount(
        householdId: householdId,
        name: 'Leo',
        email: 'pat+leo@example.com',
        password: 'secret1',
        age: 7,
      );
      expect(uid, 'new-kid');
      expect(createdProfile?['createdByParentId'], 'parent-1');
      expect(createdProfile?['role'], 'child');
      final household = await firestore
          .collection('households')
          .doc(householdId)
          .get();
      expect(household.data()?['memberIds'], ['parent-1', 'new-kid']);
    });
  });

  group('renameHousehold', () {
    Future<String?> storedName() async =>
        (await firestore.collection('households').doc(householdId).get()).data()?['name'] as String?;

    test('the admin can rename the household (spaces tidied)', () async {
      await seedHousehold();
      db.bindSession(parent);
      await pumpEventQueue();

      await db.renameHousehold('  The   Pat   Crew ');
      await pumpEventQueue();

      expect(await storedName(), 'The Pat Crew');
      expect(db.household?.name, 'The Pat Crew');
    });

    test('a member who is not the admin cannot rename it', () async {
      await seedHousehold();
      db.bindSession(child);
      await pumpEventQueue();

      await expectLater(db.renameHousehold('Kid Kingdom'), throwsA(isA<Exception>()));
      expect(await storedName(), 'The Pats');
    });

    test('rejects empty and too-long names', () async {
      await seedHousehold();
      db.bindSession(parent);
      await pumpEventQueue();

      await expectLater(db.renameHousehold('   '), throwsA(isA<Exception>()));
      await expectLater(db.renameHousehold('x' * 41), throwsA(isA<Exception>()));
      expect(await storedName(), 'The Pats');
    });
  });
}
