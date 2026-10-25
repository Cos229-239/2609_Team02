import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/goal.dart';
import 'package:famotive/core/services/database_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late DatabaseService db;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    db = DatabaseService(
      firestore: firestore,
      deviceTimeZone: () async => null,
    );
  });

  tearDown(() {
    db.dispose();
  });

  Future<void> seedGoal(String householdId, String goalId) async {
    final goal = Goal(
      id: goalId,
      title: 'Challenge $goalId',
      type: GoalType.family,
      metric: GoalMetric.tasksCompleted,
      period: GoalPeriod.weekly,
      targetValue: 5,
      startsAt: DateTime(2026, 10, 1),
      endsAt: DateTime(2026, 10, 8),
    );

    await firestore
        .collection('households')
        .doc(householdId)
        .collection('goals')
        .doc(goalId)
        .set(goal.toFirestore());
  }

  test('goals remain isolated when switching households', () async {
    await seedGoal('household-a', 'goal-a');
    await seedGoal('household-b', 'goal-b');

    db.bindHousehold('household-a');
    await pumpEventQueue();

    expect(db.goals.map((goal) => goal.id), ['goal-a']);

    db.bindHousehold('household-b');

    // Previous household data must be cleared synchronously.
    expect(db.goals, isEmpty);

    await pumpEventQueue();

    expect(db.goals.map((goal) => goal.id), ['goal-b']);
    expect(db.goals.map((goal) => goal.id), isNot(contains('goal-a')));

    db.bindHousehold('household-a');
    await pumpEventQueue();

    expect(db.goals.map((goal) => goal.id), ['goal-a']);
  });

  test('goals update when Firestore data changes', () async {
    db.bindHousehold('household-a');
    await pumpEventQueue();

    expect(db.goals, isEmpty);

    // Create a challenge while the household is already active.
    await seedGoal('household-a', 'goal-1');
    await pumpEventQueue();

    expect(db.goals.length, 1);
    expect(db.goals.single.id, 'goal-1');
    expect(db.goals.single.currentProgress, 0);

    // Simulate challenge progress changing after task approval.
    await firestore
        .collection('households')
        .doc('household-a')
        .collection('goals')
        .doc('goal-1')
        .update({'currentProgress': 3});

    await pumpEventQueue();

    expect(db.goals.single.currentProgress, 3);

    // Remove the challenge.
    await firestore
        .collection('households')
        .doc('household-a')
        .collection('goals')
        .doc('goal-1')
        .delete();

    await pumpEventQueue();

    expect(db.goals, isEmpty);
  });
  test(
    'createChallenge rejects creation without an active household',
    () async {
      final goal = Goal(
        id: 'goal-1',
        title: 'Complete 5 Tasks',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        startsAt: DateTime(2026, 10, 1),
        endsAt: DateTime(2026, 10, 8),
      );

      await expectLater(
        db.createChallenge(goal: goal, taskIds: const []),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Cannot create a challenge without an active household.',
          ),
        ),
      );
    },
  );

  test('createChallenge creates a goal and links selected tasks', () async {
    const householdId = 'household-1';

    final householdRef = firestore.collection('households').doc(householdId);
    final tasksRef = householdRef.collection('tasks');

    await householdRef.set({
      'name': 'Test Household',
      'ownerId': 'parent-1',
      'memberIds': ['parent-1', 'child-1'],
    });

    // Create two eligible tasks.
    await tasksRef
        .doc('task-1')
        .set(TaskModel(id: 'task-1', title: 'Wash dishes').toFirestore());

    await tasksRef
        .doc('task-2')
        .set(TaskModel(id: 'task-2', title: 'Clean bedroom').toFirestore());

    db.bindHousehold(householdId);
    await pumpEventQueue();

    final goal = Goal(
      id: '',
      title: 'Kitchen Cleanup Week',
      type: GoalType.family,
      metric: GoalMetric.tasksCompleted,
      period: GoalPeriod.weekly,
      targetValue: 1,
      startsAt: DateTime(2026, 10, 12),
      endsAt: DateTime(2026, 10, 19),
    );

    // Create through DatabaseService, not GoalService directly.
    final goalId = await db.createChallenge(goal: goal, taskIds: ['task-1']);

    await pumpEventQueue();

    // Verify the goal was saved in the active household.
    final savedGoal = await householdRef.collection('goals').doc(goalId).get();

    expect(goalId, isNotEmpty);
    expect(savedGoal.exists, isTrue);
    expect(savedGoal.data()?['title'], 'Kitchen Cleanup Week');
    expect(savedGoal.data()?['currentProgress'], 0);

    // Verify the selected task is linked.
    final selectedTask = await tasksRef.doc('task-1').get();
    expect(selectedTask.data()?['goalId'], goalId);

    // Verify the unselected task remains unchanged.
    final unselectedTask = await tasksRef.doc('task-2').get();
    expect(unselectedTask.data()?['goalId'], isNull);

    // Verify the live subscription received the new challenge.
    expect(db.goals.length, 1);
    expect(db.goals.single.id, goalId);
    expect(db.goals.single.title, 'Kitchen Cleanup Week');
  });

  test('createChallenge saves existing and new tasks together', () async {
    const householdId = 'household-1';

    final householdRef = firestore.collection('households').doc(householdId);
    final tasksRef = householdRef.collection('tasks');

    await householdRef.set({
      'name': 'Test Household',
      'ownerId': 'parent-1',
      'memberIds': ['parent-1', 'child-1'],
    });

    await tasksRef
        .doc('existing-task')
        .set(
          TaskModel(id: 'existing-task', title: 'Wash dishes').toFirestore(),
        );

    await tasksRef
        .doc('unselected-task')
        .set(
          TaskModel(
            id: 'unselected-task',
            title: 'Clean bedroom',
          ).toFirestore(),
        );

    db.bindHousehold(householdId);
    await pumpEventQueue();

    final goal = Goal(
      id: '',
      title: 'Weekend Cleanup',
      type: GoalType.family,
      metric: GoalMetric.tasksCompleted,
      period: GoalPeriod.weekly,
      targetValue: 2,
      startsAt: DateTime(2026, 10, 24),
      endsAt: DateTime(2026, 10, 31),
    );

    final goalId = await db.createChallenge(
      goal: goal,
      taskIds: ['existing-task'],
      newTasks: [TaskModel(id: '', title: 'Take out trash')],
    );

    final savedGoal = await householdRef.collection('goals').doc(goalId).get();

    expect(savedGoal.exists, isTrue);
    expect(savedGoal.data()?['taskScope'], 'linkedTasksOnly');

    final existingTask = await tasksRef.doc('existing-task').get();
    expect(existingTask.data()?['goalId'], goalId);

    final unselectedTask = await tasksRef.doc('unselected-task').get();
    expect(unselectedTask.data()?['goalId'], isNull);

    final allTasks = await tasksRef.get();

    final newTasks = allTasks.docs.where(
      (doc) => doc.data()['title'] == 'Take out trash',
    );

    expect(newTasks.length, 1);
    expect(newTasks.single.data()['goalId'], goalId);

    final linkedTasks = allTasks.docs.where(
      (doc) => doc.data()['goalId'] == goalId,
    );

    expect(linkedTasks.length, 2);
  });
}
