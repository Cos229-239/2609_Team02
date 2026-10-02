/**
 * Pure decision logic: given a Firestore change, which notifications
 * should go out and to whom. Kept free of any Firebase imports so it can
 * be unit tested with plain `node --test` (see plan.test.ts).
 */

export type NotificationKind =
  // To children
  | 'task_available' // new unassigned task in the shared pool
  | 'task_assigned' // a parent assigned a task to this child
  | 'task_due' // assigned task is due today
  | 'task_overdue' // assigned task is past due
  | 'task_approved' // a parent approved the child's completed task
  | 'daily_digest' // morning summary: several due / overdue / up-for-grabs tasks
  // To parents
  | 'task_accepted' // a child claimed a task from the pool
  | 'task_completed' // a child marked a task done (awaiting approval)
  | 'reward_redeemed' // a child redeemed a reward from the store
  // Household membership
  | 'join_requested' // to the admin: someone entered the invite code
  | 'household_joined'; // to the new member: the admin let them in

export type Audience =
  | { type: 'user'; userId: string }
  | { type: 'children' }
  | { type: 'parents' }
  /** Every member, regardless of role (used with explicit user lists). */
  | { type: 'users'; userIds: string[] };

export interface PlannedNotification {
  kind: NotificationKind;
  audience: Audience;
  /** Never notify these users (normally: whoever made the change). */
  excludeUserIds: string[];
}

/** The subset of a `households/{id}/tasks/{taskId}` doc the planner reads. */
export interface TaskData {
  title?: string;
  assignedToUserId?: string | null;
  status?: string;
  archived?: boolean;
  dueDate?: Date | null;
  /** Written by the app's `claimTask` — fallback when auth context is missing. */
  claimedBy?: string | null;
  /** Set on occurrences the server generates from a repeating schedule. */
  scheduleId?: string | null;
}

const exclude = (actorId: string | undefined): string[] => (actorId ? [actorId] : []);

/** A task document was created. */
export function planTaskCreated(task: TaskData, actorId?: string): PlannedNotification[] {
  if (task.archived) return [];
  // Occurrences of repeating tasks are announced by the 9 AM digest instead,
  // not one push per chore per day.
  if (task.scheduleId) return [];
  if ((task.status ?? 'pending') !== 'pending') return [];

  const assignee = task.assignedToUserId ?? null;
  if (assignee) {
    if (assignee === actorId) return [];
    return [{ kind: 'task_assigned', audience: { type: 'user', userId: assignee }, excludeUserIds: [] }];
  }
  return [{ kind: 'task_available', audience: { type: 'children' }, excludeUserIds: exclude(actorId) }];
}

/** A task document was updated. */
export function planTaskUpdated(
  before: TaskData,
  after: TaskData,
  actorId?: string,
): PlannedNotification[] {
  if (after.archived) return [];

  const out: PlannedNotification[] = [];
  const assignee = after.assignedToUserId ?? null;

  // --- (Re)assignment ------------------------------------------------------
  if (assignee && assignee !== (before.assignedToUserId ?? null)) {
    const isClaim = actorId
      ? actorId === assignee
      : after.claimedBy === assignee && before.claimedBy !== assignee;

    if (isClaim) {
      out.push({ kind: 'task_accepted', audience: { type: 'parents' }, excludeUserIds: exclude(actorId) });
    } else {
      out.push({ kind: 'task_assigned', audience: { type: 'user', userId: assignee }, excludeUserIds: [] });
    }
  }

  // --- Status transitions --------------------------------------------------
  const wasStatus = before.status ?? 'pending';
  const isStatus = after.status ?? 'pending';

  if (wasStatus !== 'completed' && isStatus === 'completed') {
    out.push({ kind: 'task_completed', audience: { type: 'parents' }, excludeUserIds: exclude(actorId) });
  }

  if (wasStatus !== 'approved' && isStatus === 'approved' && assignee && assignee !== actorId) {
    out.push({ kind: 'task_approved', audience: { type: 'user', userId: assignee }, excludeUserIds: [] });
  }

  return out;
}

/** Someone filed a join request: only the admin can act on it. */
export function planJoinRequested(ownerId: string | null | undefined, requesterId: string): PlannedNotification[] {
  if (!ownerId || ownerId === requesterId) return [];
  return [{ kind: 'join_requested', audience: { type: 'user', userId: ownerId }, excludeUserIds: [] }];
}

/**
 * memberIds changed: welcome whoever was added (by the admin approving
 * them, or a parent creating a child account), except whoever did it.
 */
export function planMembersAdded(before: string[], after: string[], actorId?: string): PlannedNotification[] {
  const added = after.filter((id) => !before.includes(id) && id !== actorId);
  if (added.length === 0) return [];
  return [{ kind: 'household_joined', audience: { type: 'users', userIds: added }, excludeUserIds: [] }];
}

/** A redemption document was created. */
export function planRedemptionCreated(actorId?: string): PlannedNotification[] {
  return [{ kind: 'reward_redeemed', audience: { type: 'parents' }, excludeUserIds: exclude(actorId) }];
}

// --- Morning run: due today / overdue digest -----------------------------------

/** A task as the morning run sees it: `day` is its due date's local day. */
export interface MorningTask {
  id: string;
  title?: string;
  assignedToUserId?: string | null;
  status?: string;
  archived?: boolean;
  /** Local day ('YYYY-MM-DD') of `dueDate` in the household's zone. */
  day: string;
  /** Set on occurrences generated from a repeating schedule. */
  scheduleId?: string | null;
}

export interface MorningPlan {
  /** Per child: their pending tasks due today, and yesterday's still pending. */
  children: Map<string, { due: MorningTask[]; overdue: MorningTask[] }>;
  /** Unclaimed pending tasks due today — every child hears about these. */
  pool: MorningTask[];
  /**
   * Generated occurrences that were missed (pending, due before yesterday):
   * archived so a skipped daily chore doesn't pile up in the child's list.
   */
  toArchive: string[];
}

/** Groups a household's recent tasks for the [today] morning run. */
export function planMorning(tasks: MorningTask[], today: string, yesterday: string): MorningPlan {
  const plan: MorningPlan = { children: new Map(), pool: [], toArchive: [] };
  const bucket = (uid: string) => {
    let b = plan.children.get(uid);
    if (!b) plan.children.set(uid, (b = { due: [], overdue: [] }));
    return b;
  };

  for (const t of tasks) {
    if (t.archived || (t.status ?? 'pending') !== 'pending') continue;
    const assignee = t.assignedToUserId ?? null;
    if (t.day === today) {
      if (assignee) bucket(assignee).due.push(t);
      else plan.pool.push(t);
    } else if (t.day === yesterday) {
      if (assignee) bucket(assignee).overdue.push(t);
    } else if (t.day < yesterday && t.scheduleId) {
      plan.toArchive.push(t.id);
    }
  }
  return plan;
}

export interface DigestItems {
  due: MorningTask[];
  overdue: MorningTask[];
  pool: MorningTask[];
}

/**
 * One morning notification for a child, or null if there's nothing to say.
 * A single item keeps its specific kind (and opens that task); anything more
 * becomes one `daily_digest` so a child with five chores gets one push.
 */
export function planDigest(items: DigestItems): { kind: NotificationKind; task?: MorningTask } | null {
  const total = items.due.length + items.overdue.length + items.pool.length;
  if (total === 0) return null;
  if (total > 1) return { kind: 'daily_digest' };
  if (items.due.length) return { kind: 'task_due', task: items.due[0] };
  if (items.overdue.length) return { kind: 'task_overdue', task: items.overdue[0] };
  return { kind: 'task_available', task: items.pool[0] };
}
