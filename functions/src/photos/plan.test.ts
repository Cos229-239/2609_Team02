import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ownPhotoPath, photoPrefix, planPhotoWrite, PHOTO_RETENTION_MS } from './plan';

const ts = (ms: number) => ({ toMillis: () => ms });
const NOW = Date.UTC(2026, 9, 2, 12);
const path = (file = '1.jpg', h = 'h1', t = 't1') => `households/${h}/taskPhotos/${t}/${file}`;
const task = (photoPath?: string, deleteAt?: number) => ({
  title: 'Clean your bedroom',
  status: photoPath ? 'completed' : 'pending',
  ...(photoPath ? { proof: { photoPath, deleteAt: deleteAt === undefined ? undefined : ts(deleteAt) } } : {}),
});

test('ownPhotoPath accepts only files in the task\'s own folder', () => {
  assert.equal(ownPhotoPath(task(path()), 'h1', 't1'), path());
  assert.equal(ownPhotoPath(task(path('1.jpg', 'other')), 'h1', 't1'), null);
  assert.equal(ownPhotoPath(task(path('1.jpg', 'h1', 't2')), 'h1', 't1'), null);
  assert.equal(ownPhotoPath(task(path('../x/1.jpg')), 'h1', 't1'), null);
  assert.equal(ownPhotoPath(task(photoPrefix('h1', 't1')), 'h1', 't1'), null);
  assert.equal(ownPhotoPath({ proof: { photoPath: 42 } }, 'h1', 't1'), null);
  assert.equal(ownPhotoPath(undefined, 'h1', 't1'), null);
});

test('deleting a task deletes its photo by exact path', () => {
  const plan = planPhotoWrite(task(path()), undefined, 'h1', 't1', NOW);
  assert.deepEqual(plan.deleteFiles, [path()]);
});

test('deleting a task without a photo touches Storage not at all', () => {
  assert.deepEqual(planPhotoWrite(task(), undefined, 'h1', 't1', NOW), { deleteFiles: [], fixDeleteAtMs: null });
  assert.deepEqual(planPhotoWrite(task(path('1.jpg', 'evil')), undefined, 'h1', 't1', NOW).deleteFiles, []);
});

test('sending a task back (proof cleared) deletes the old photo', () => {
  const plan = planPhotoWrite(task(path(), NOW + 1000), task(), 'h1', 't1', NOW);
  assert.deepEqual(plan.deleteFiles, [path()]);
  assert.equal(plan.fixDeleteAtMs, null);
});

test('a replaced photo deletes the previous one', () => {
  const plan = planPhotoWrite(task(path('1.jpg'), NOW), task(path('2.jpg'), NOW + PHOTO_RETENTION_MS), 'h1', 't1', NOW);
  assert.deepEqual(plan.deleteFiles, [path('1.jpg')]);
});

test('unrelated edits leave the photo alone', () => {
  const plan = planPhotoWrite(task(path(), NOW + PHOTO_RETENTION_MS), task(path(), NOW + PHOTO_RETENTION_MS), 'h1', 't1', NOW);
  assert.deepEqual(plan, { deleteFiles: [], fixDeleteAtMs: null });
});

test('a foreign path is never deleted', () => {
  const plan = planPhotoWrite(task(path('1.jpg', 'victim', 't9')), task(), 'h1', 't1', NOW);
  assert.deepEqual(plan.deleteFiles, []);
});

test('missing or too-late deleteAt is corrected to the retention limit', () => {
  assert.equal(planPhotoWrite(task(), task(path()), 'h1', 't1', NOW).fixDeleteAtMs, NOW + PHOTO_RETENTION_MS);
  const late = NOW + 30 * 24 * 60 * 60 * 1000;
  assert.equal(planPhotoWrite(task(), task(path(), late), 'h1', 't1', NOW).fixDeleteAtMs, NOW + PHOTO_RETENTION_MS);
  assert.equal(planPhotoWrite(task(), task(path(), NOW + PHOTO_RETENTION_MS - 5000), 'h1', 't1', NOW).fixDeleteAtMs, null);
});

test('creating a task with no proof does nothing', () => {
  assert.deepEqual(planPhotoWrite(undefined, task(), 'h1', 't1', NOW), { deleteFiles: [], fixDeleteAtMs: null });
});
