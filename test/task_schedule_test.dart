import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task_schedule.dart';

void main() {
  TaskSchedule schedule(TaskRepeat repeat, {List<int> weekdays = const [], DateTime? start}) => TaskSchedule(
        id: 's1',
        title: 'Feed the Dog',
        repeat: repeat,
        weekdays: weekdays,
        startDate: start ?? DateTime(2026, 10, 7), // a Wednesday
      );

  group('dayKey', () {
    test('round-trips', () {
      expect(dayKey(DateTime(2026, 3, 9, 17)), '2026-03-09');
      expect(parseDayKey('2026-03-09'), DateTime(2026, 3, 9));
      expect(parseDayKey('nope'), isNull);
      expect(parseDayKey(null), isNull);
    });
  });

  group('TaskSchedule.describe', () {
    test('every cadence', () {
      expect(schedule(TaskRepeat.daily).describe(), 'Every day');
      expect(schedule(TaskRepeat.everyOtherDay).describe(), 'Every other day');
      expect(schedule(TaskRepeat.weekly, weekdays: [4, 1]).describe(), 'Every Mon & Thu');
      expect(schedule(TaskRepeat.weekly, weekdays: [1, 3, 5]).describe(), 'Every Mon, Wed & Fri');
      expect(schedule(TaskRepeat.weekly, weekdays: [1, 2, 3, 4, 5, 6, 7]).describe(), 'Every day');
      expect(schedule(TaskRepeat.everyOtherWeek, weekdays: [2]).describe(), 'Every other Tue');
      expect(schedule(TaskRepeat.monthly, start: DateTime(2026, 1, 31)).describe(), 'Monthly on the 31st');
      expect(schedule(TaskRepeat.monthly, start: DateTime(2026, 1, 12)).describe(), 'Monthly on the 12th');
      expect(schedule(TaskRepeat.monthly, start: DateTime(2026, 1, 22)).describe(), 'Monthly on the 22nd');
    });

    test('weekly with no weekdays uses the start day', () {
      expect(schedule(TaskRepeat.weekly).effectiveWeekdays, [DateTime.wednesday]);
      expect(schedule(TaskRepeat.weekly).describe(), 'Every Wed');
    });
  });

  group('TaskSchedule Firestore', () {
    test('round-trips and only stores weekdays for weekly cadences', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('taskSchedules').doc('s1');

      await ref.set(schedule(TaskRepeat.everyOtherWeek, weekdays: [5, 1]).toFirestore());
      final back = TaskSchedule.fromFirestore(await ref.get())!;
      expect(back.repeat, TaskRepeat.everyOtherWeek);
      expect(back.weekdays, [1, 5]);
      expect(back.startDate, DateTime(2026, 10, 7));
      expect((await ref.get()).data()!['startDate'], '2026-10-07');

      expect(schedule(TaskRepeat.daily, weekdays: [1]).toFirestore()['weekdays'], isEmpty);
    });

    test('unknown repeat values are ignored', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('taskSchedules').doc('bad');
      await ref.set({'title': 'x', 'repeat': 'yearly', 'startDate': '2026-10-07'});
      expect(TaskSchedule.fromFirestore(await ref.get()), isNull);
    });
  });

  test('starter schedules start today', () {
    final seeds = TaskSchedule.defaultCatalog(DateTime(2026, 10, 1, 18, 30));
    expect(seeds, isNotEmpty);
    for (final s in seeds) {
      expect(s.startDate, DateTime(2026, 10, 1));
    }
  });
}
