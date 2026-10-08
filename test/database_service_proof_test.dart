import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/constants/app_constants.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/task_proof.dart';
import 'package:famotive/core/services/database_service.dart';

void main() {
  const householdId = 'household-1';
  late FakeFirebaseFirestore firestore;
  late DatabaseService db;

  CollectionReference<Map<String, dynamic>> tasks() =>
      firestore.collection('households').doc(householdId).collection('tasks');

  Future<TaskModel> load(String id) async => TaskModel.fromFirestore(await tasks().doc(id).get());

  const scanMatch = TaskScanResult(verdict: ScanVerdict.match, score: 0.8, labels: [ScanLabel('bed', 0.8)]);
  const scanUnsure = TaskScanResult(verdict: ScanVerdict.uncertain, score: 0.3);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    db = DatabaseService(firestore: firestore, deviceTimeZone: () async => null);
    db.bindHousehold(householdId);
    await tasks().doc('t1').set(const TaskModel(
      id: 't1',
      title: 'Clean your bedroom',
      assignedToUserId: 'child-1',
      requiresPhoto: true,
    ).toFirestore());
    await firestore.collection('users').doc('child-1').set({'xp': 0, 'coins': 0});
  });

  test('requiresPhoto round-trips; proof is never written by toFirestore', () async {
    final task = await load('t1');
    expect(task.requiresPhoto, isTrue);
    expect(task.toFirestore().containsKey('proof'), isFalse);
  });

  test('submitTaskProof completes the task with photo, scan and 7-day deletion', () async {
    final now = DateTime(2026, 10, 2, 18);
    await db.submitTaskProof('t1', photoPath: 'households/$householdId/taskPhotos/t1/1.jpg', scan: scanMatch, now: now);

    final task = await load('t1');
    expect(task.status, TaskStatus.completed);
    expect(task.completedAt, now);
    expect(task.proof?.photoPath, 'households/$householdId/taskPhotos/t1/1.jpg');
    expect(task.proof?.deleteAt, now.add(const Duration(days: AppConstants.taskPhotoRetentionDays)));
    expect(task.proof?.verdict, ScanVerdict.match);
    expect(task.proofNeedsReview, isFalse);
  });

  test('cannot submit proof for a task that is already done', () async {
    await db.submitTaskProof('t1', photoPath: 'p', scan: scanMatch);
    await expectLater(db.submitTaskProof('t1', photoPath: 'p2', scan: scanMatch), throwsException);
  });

  test('approving an uncertain scan records the parent override and grants rewards', () async {
    await db.submitTaskProof('t1', photoPath: 'p', scan: scanUnsure);
    expect((await load('t1')).proofNeedsReview, isTrue);

    await db.approveTask('t1');
    final task = await load('t1');
    expect(task.status, TaskStatus.approved);
    expect(task.proof?.parentOverride, isTrue);
    final child = await firestore.collection('users').doc('child-1').get();
    expect(child.data()?['xp'], AppConstants.defaultTaskXp);
  });

  test('approving a matching scan is not an override', () async {
    await db.submitTaskProof('t1', photoPath: 'p', scan: scanMatch);
    await db.approveTask('t1');
    expect((await load('t1')).proof?.parentOverride, isFalse);
  });

  test('sending back clears the proof (server then deletes the photo)', () async {
    await db.submitTaskProof('t1', photoPath: 'p', scan: scanUnsure);
    await db.uncompleteTask('t1');
    final task = await load('t1');
    expect(task.status, TaskStatus.pending);
    expect(task.proof, isNull);
    expect(task.requiresPhoto, isTrue);
  });
}
