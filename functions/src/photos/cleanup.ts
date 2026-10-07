// Task proof photo retention (Storage).
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

import { ownPhotoPath, planPhotoWrite } from './plan';

const TASK_PATH = 'households/{householdId}/tasks/{taskId}';
const PURGE_BATCH = 300;

async function deleteFile(path: string): Promise<void> {
  await getStorage().bucket().file(path).delete({ ignoreNotFound: true });
}

export const cleanUpTaskPhotos = onDocumentWritten(TASK_PATH, async (event) => {
  const { householdId, taskId } = event.params;
  const before = event.data?.before.exists ? event.data.before.data() : undefined;
  const after = event.data?.after.exists ? event.data.after.data() : undefined;
  const nowMs = Date.parse(event.time) || Date.now();

  const plan = planPhotoWrite(before, after, householdId, taskId, nowMs);
  for (const path of plan.deleteFiles) {
    await deleteFile(path);
    logger.info('Deleted task photo', { householdId, taskId, taskDeleted: !after });
  }
  if (plan.fixDeleteAtMs !== null && event.data?.after.exists) {
    await event.data.after.ref.update({ 'proof.deleteAt': Timestamp.fromMillis(plan.fixDeleteAtMs) });
  }
});

export const purgeExpiredTaskPhotos = onSchedule({ schedule: 'every 6 hours', timeZone: 'UTC' }, async () => {
  const db = getFirestore();
  const now = Timestamp.now();
  let total = 0;
  let failed = 0;
  // Page with a cursor instead of re-running the same query: a document
  // that fails stays due, and re-querying from the top would hand back the
  // same failing batch forever. Failures are left for the next scheduled run.
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let query = db
      .collectionGroup('tasks')
      .where('proof.deleteAt', '<=', now)
      .orderBy('proof.deleteAt')
      .limit(PURGE_BATCH);
    if (cursor) query = query.startAfter(cursor);
    const due = await query.get();
    if (due.empty) break;
    cursor = due.docs[due.docs.length - 1];
    for (const doc of due.docs) {
      const householdId = doc.ref.parent.parent?.id;
      if (!householdId) continue;
      try {
        const path = ownPhotoPath(doc.data(), householdId, doc.id);
        if (path) await deleteFile(path);
        await doc.ref.update({
          'proof.photoPath': FieldValue.delete(),
          'proof.deleteAt': FieldValue.delete(),
          'proof.photoDeletedAt': now,
        });
        total++;
      } catch (err) {
        failed++;
        logger.error('Deleting expired task photo failed', { path: doc.ref.path, err });
      }
    }
    if (due.size < PURGE_BATCH) break;
  }
  if (total || failed) logger.info('Expired task photo cleanup', { deleted: total, failed });
});
