// Task proof photo rules.
export const PHOTO_RETENTION_DAYS = 7;
export const PHOTO_RETENTION_MS = PHOTO_RETENTION_DAYS * 24 * 60 * 60 * 1000;

const DELETE_AT_TOLERANCE_MS = 60 * 60 * 1000;

/** Storage folder holding one task's photos. */
export function photoPrefix(householdId: string, taskId: string): string {
  return `households/${householdId}/taskPhotos/${taskId}/`;
}

export function ownPhotoPath(data: unknown, householdId: string, taskId: string): string | null {
  const proof = (data as { proof?: unknown } | null | undefined)?.proof;
  const path = (proof as { photoPath?: unknown } | null | undefined)?.photoPath;
  if (typeof path !== 'string') return null;
  const prefix = photoPrefix(householdId, taskId);
  if (!path.startsWith(prefix)) return null;
  const name = path.slice(prefix.length);
  if (!name || name.includes('/') || name.includes('..')) return null;
  return path;
}

export function millisOf(value: unknown): number | null {
  const fn = (value as { toMillis?: unknown } | null | undefined)?.toMillis;
  if (typeof fn !== 'function') return null;
  const ms = (fn as () => unknown).call(value);
  return typeof ms === 'number' && Number.isFinite(ms) ? ms : null;
}

export interface PhotoWritePlan {
  deleteFiles: string[];
  fixDeleteAtMs: number | null;
}

export function planPhotoWrite(
  before: unknown,
  after: unknown,
  householdId: string,
  taskId: string,
  nowMs: number,
): PhotoWritePlan {
  const plan: PhotoWritePlan = { deleteFiles: [], fixDeleteAtMs: null };

  // Exact paths only: deletes are free, folder listings are Class A ops.
  if (after === undefined || after === null) {
    const path = ownPhotoPath(before, householdId, taskId);
    if (path) plan.deleteFiles.push(path);
    return plan;
  }

  const oldPath = ownPhotoPath(before, householdId, taskId);
  const newPath = ownPhotoPath(after, householdId, taskId);
  if (oldPath && oldPath !== newPath) plan.deleteFiles.push(oldPath);

  if (newPath) {
    const proof = (after as { proof?: Record<string, unknown> }).proof ?? {};
    const deleteAt = millisOf(proof.deleteAt);
    const latest = nowMs + PHOTO_RETENTION_MS;
    if (deleteAt === null || deleteAt > latest + DELETE_AT_TOLERANCE_MS) plan.fixDeleteAtMs = latest;
  }
  return plan;
}
