import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/task_schedule.dart';
import 'package:famotive/core/services/database_service.dart';

void main() {
  const householdId = 'household-1';
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  DocumentRefs refs() => DocumentRefs(firestore, householdId);

  group('DatabaseService repeating tasks', () {
    late DatabaseService db;

    setUp(() {
      db = DatabaseService(firestore: firestore, deviceTimeZone: () async => null);
      db.bindHousehold(householdId);
    });

    test('add, list, update and delete a schedule', () async {
      final id = await db.addSchedule(TaskSchedule(
        id: '',
        title: 'Feed the Dog',
        repeat: TaskRepeat.weekly,
        weekdays: const [1, 4],
        startDate: DateTime(2026, 10, 5),
      ));
      await pumpEventQueue();
      expect(db.schedules.single.describe(), 'Every Mon & Thu');
      expect(db.scheduleById(id)?.title, 'Feed the Dog');

      // The server's bookkeeping survives a client edit.
      await refs().schedules.doc(id).update({'generatedThrough': '2026-10-06'});
      await db.updateSchedule(id, db.scheduleById(id)!.copyWith(title: 'Feed Rex'));
      final saved = (await refs().schedules.doc(id).get()).data()!;
      expect(saved['title'], 'Feed Rex');
      expect(saved['generatedThrough'], '2026-10-06');

      await db.deleteSchedule(id);
      await pumpEventQueue();
      expect(db.schedules, isEmpty);
    });

    test("tomorrow's generated occurrence stays hidden until its day", () async {
      final now = DateTime.now();
      await refs().tasks.doc('s1_today').set(TaskModel(
            id: 's1_today',
            title: 'Dog',
            scheduleId: 's1',
            repeat: TaskRepeat.daily,
            dueDate: DateTime(now.year, now.month, now.day),
          ).toFirestore());
      await refs().tasks.doc('s1_tomorrow').set(TaskModel(
            id: 's1_tomorrow',
            title: 'Dog',
            scheduleId: 's1',
            repeat: TaskRepeat.daily,
            dueDate: DateTime(now.year, now.month, now.day + 1),
          ).toFirestore());
      await pumpEventQueue();
      expect(db.tasks, hasLength(2));
      expect(db.activeTasks.map((t) => t.id), ['s1_today']);
    });
  });

  group('household time zone backfill', () {
    test('fills in a missing zone from the device', () async {
      await refs().household.set({'name': 'Fam', 'memberIds': <String>[]});
      final db = DatabaseService(firestore: firestore, deviceTimeZone: () async => 'America/Chicago');
      db.bindHousehold(householdId);
      await pumpEventQueue();
      expect((await refs().household.get()).data()!['timezone'], 'America/Chicago');
      expect(db.household?.timezone, 'America/Chicago');
    });

    test('never overwrites an existing zone', () async {
      await refs().household.set({'name': 'Fam', 'memberIds': <String>[], 'timezone': 'Europe/London'});
      final db = DatabaseService(firestore: firestore, deviceTimeZone: () async => 'America/Chicago');
      db.bindHousehold(householdId);
      await pumpEventQueue();
      expect((await refs().household.get()).data()!['timezone'], 'Europe/London');
    });
  });
}

class DocumentRefs {
  DocumentRefs(this.firestore, this.householdId);

  final FakeFirebaseFirestore firestore;
  final String householdId;

  DocumentReference<Map<String, dynamic>> get household => firestore.collection('households').doc(householdId);
  CollectionReference<Map<String, dynamic>> get tasks => household.collection('tasks');
  CollectionReference<Map<String, dynamic>> get schedules => household.collection('taskSchedules');
}
