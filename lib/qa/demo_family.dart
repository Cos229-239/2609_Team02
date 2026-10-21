import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

import '../core/models/household.dart';
import '../core/models/redemption.dart';
import '../core/models/reward.dart';
import '../core/models/task.dart';
import '../core/models/task_schedule.dart';
import '../core/models/user.dart';
import '../core/services/auth_service.dart';

/// A signed-in session of the full app on made-up data, for the QA build.
///
/// Everything lives in memory: an in-memory Firestore and a mock Firebase
/// Auth, created fresh for every run and thrown away at "End test". The QA
/// build never calls `Firebase.initializeApp`, so even a stray call to a
/// default `FirebaseFirestore.instance` fails instead of touching real data.
class DemoSession {
  DemoSession._(this.firestore, this.authService, this.user);

  final FakeFirebaseFirestore firestore;
  final AuthService authService;
  final AppUser user;

  /// Builds the sample household and signs in as its parent or child.
  static Future<DemoSession> start(UserRole role, {DateTime? now}) async {
    final firestore = FakeFirebaseFirestore();
    await DemoFamily.seed(firestore, now: now ?? DateTime.now());

    final user = role == UserRole.parent ? DemoFamily.parent : DemoFamily.maya;
    final auth = AuthService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: user.id, email: user.email, displayName: user.name),
      ),
      firestore: firestore,
      // "Add child" normally signs the child up on a second Firebase app.
      childAccountCreator: ({required email, required password, required profile}) async {
        final ref = firestore.collection('users').doc();
        await ref.set({...profile, 'createdAt': FieldValue.serverTimestamp()});
        return ref.id;
      },
      // Account deletion is a Cloud Function: not available in the demo.
      accountDeletionCall: (_) async =>
          throw Exception('Deleting accounts is turned off in this test. Nothing is saved anyway.'),
    );
    await auth.tryRestoreSession();
    return DemoSession._(firestore, auth, auth.currentUser ?? user);
  }
}

/// The Rivera Household: one parent (the household admin) and two kids,
/// with tasks in every state, repeating chores and the starter rewards.
class DemoFamily {
  DemoFamily._();

  static const householdId = 'demo-household';
  static const householdName = 'The Rivera Household';

  static const parent = AppUser(
    id: 'demo-parent',
    name: 'Alex Rivera',
    email: 'alex@example.com',
    role: UserRole.parent,
    avatarEmoji: '👩',
    householdId: householdId,
  );

  static const maya = AppUser(
    id: 'demo-maya',
    name: 'Maya Rivera',
    email: 'maya@example.com',
    role: UserRole.child,
    avatarEmoji: '🦸',
    age: 11,
    xp: 340,
    coins: 85,
    householdId: householdId,
    createdByParentId: 'demo-parent',
  );

  static const leo = AppUser(
    id: 'demo-leo',
    name: 'Leo Rivera',
    email: 'leo@example.com',
    role: UserRole.child,
    avatarEmoji: '🦖',
    age: 7,
    xp: 120,
    coins: 30,
    householdId: householdId,
    createdByParentId: 'demo-parent',
  );

  static Future<void> seed(FirebaseFirestore firestore, {required DateTime now}) async {
    final today = DateTime(now.year, now.month, now.day);
    DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);

    final users = firestore.collection('users');
    for (final u in [parent, maya, leo]) {
      await users.doc(u.id).set({...u.toFirestore(), 'createdAt': Timestamp.fromDate(day(-30))});
    }

    final household = firestore.collection('households').doc(householdId);
    await household.set(Household(
      id: householdId,
      name: householdName,
      memberIds: [parent.id, maya.id, leo.id],
      ownerId: parent.id,
      inviteCode: 'DEMO42',
      timezone: 'America/Chicago',
    ).toFirestore());

    final tasks = <TaskModel>[
      // Maya
      TaskModel(
        id: 'demo-dishes',
        title: 'Empty the Dishwasher',
        description: 'Plates and bowls go in the cupboard by the sink.',
        icon: 'dishes',
        rewardXp: 30,
        coinReward: 10,
        assignedToUserId: maya.id,
        dueDate: today,
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      TaskModel(
        id: 'demo-homework',
        title: 'Finish Math Homework',
        icon: 'homework',
        rewardXp: 40,
        coinReward: 10,
        assignedToUserId: maya.id,
        dueDate: day(1),
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      TaskModel(
        id: 'demo-bed',
        title: 'Make Your Bed',
        icon: 'bed',
        rewardXp: 15,
        coinReward: 5,
        assignedToUserId: maya.id,
        status: TaskStatus.completed,
        dueDate: today,
        createdAt: now.subtract(const Duration(days: 1)),
        completedAt: now.subtract(const Duration(hours: 1)),
      ),
      TaskModel(
        id: 'demo-table-maya',
        title: 'Set the Table',
        icon: 'table',
        rewardXp: 20,
        coinReward: 5,
        assignedToUserId: maya.id,
        status: TaskStatus.approved,
        repeat: TaskRepeat.daily,
        scheduleId: 'seed-table',
        dueDate: day(-1),
        createdAt: day(-2),
        completedAt: now.subtract(const Duration(days: 1, hours: 2)),
        approvedAt: now.subtract(const Duration(days: 1, hours: 1)),
      ),
      // Leo
      TaskModel(
        id: 'demo-dog',
        title: 'Feed the Dog',
        icon: 'pet',
        rewardXp: 15,
        coinReward: 5,
        assignedToUserId: leo.id,
        repeat: TaskRepeat.daily,
        scheduleId: 'seed-dog',
        dueDate: today,
        createdAt: day(-1),
      ),
      TaskModel(
        id: 'demo-toys',
        title: 'Pick Up Your Toys',
        icon: 'cleaning',
        rewardXp: 20,
        coinReward: 5,
        assignedToUserId: leo.id,
        status: TaskStatus.completed,
        dueDate: today,
        createdAt: now.subtract(const Duration(hours: 6)),
        completedAt: now.subtract(const Duration(minutes: 20)),
      ),
      TaskModel(
        id: 'demo-plants',
        title: 'Water the Plants',
        icon: 'plant',
        rewardXp: 15,
        coinReward: 5,
        assignedToUserId: leo.id,
        status: TaskStatus.approved,
        dueDate: day(-2),
        createdAt: day(-3),
        completedAt: day(-2).add(const Duration(hours: 17)),
        approvedAt: day(-2).add(const Duration(hours: 18)),
      ),
      // Shared pool (anyone can claim)
      TaskModel(
        id: 'demo-read',
        title: 'Read for 20 Minutes',
        icon: 'reading',
        rewardXp: 20,
        coinReward: 5,
        dueDate: day(3),
        createdAt: now,
      ),
      TaskModel(
        id: 'demo-leaves',
        title: 'Rake the Leaves',
        description: 'Front yard only. Bags are in the garage.',
        icon: 'yard',
        rewardXp: 50,
        coinReward: 15,
        dueDate: day(2),
        createdAt: now,
      ),
    ];
    for (final t in tasks) {
      await household.collection('tasks').doc(t.id).set(t.toFirestore());
    }

    for (final s in TaskSchedule.defaultCatalog(day(-7))) {
      await household.collection('taskSchedules').doc(s.id).set(s.toFirestore());
    }

    for (final r in Reward.defaultCatalog) {
      await household.collection('rewards').doc(r.id).set(r.toFirestore());
    }

    final bonus = Reward.defaultCatalog.first;
    await household.collection('redemptions').doc('demo-redemption').set(Redemption(
      id: 'demo-redemption',
      rewardId: bonus.id,
      rewardTitle: bonus.title,
      rewardIcon: bonus.icon,
      childId: maya.id,
      coinCost: bonus.coinCost,
      redeemedAt: now.subtract(const Duration(hours: 3)),
    ).toFirestore());
  }
}
