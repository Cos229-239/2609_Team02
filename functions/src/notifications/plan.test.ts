import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildMessage } from './messages';
import {
  DUE_REMINDER_OFFSET_MS,
  LATE_GRACE_MS,
  OVERDUE_OFFSET_MS,
  dueSweepWindow,
  planDueReminder,
  planRedemptionCreated,
  planTaskCreated,
  planTaskUpdated,
  type NotificationKind,
  type TaskData,
} from './plan';

const PARENT = 'parent-1';
const KID = 'kid-1';
const KID2 = 'kid-2';

const kinds = (plans: { kind: NotificationKind }[]) => plans.map((p) => p.kind);

// --- Created -----------------------------------------------------------------

test('new unassigned task notifies all children except the creator', () => {
  const plans = planTaskCreated({ title: 'Dishes', assignedToUserId: null, status: 'pending' }, PARENT);
  assert.deepEqual(plans, [{ kind: 'task_available', audience: { type: 'children' }, excludeUserIds: [PARENT] }]);
});

test('new assigned task notifies the assignee', () => {
  const plans = planTaskCreated({ title: 'Dishes', assignedToUserId: KID, status: 'pending' }, PARENT);
  assert.deepEqual(plans, [{ kind: 'task_assigned', audience: { type: 'user', userId: KID }, excludeUserIds: [] }]);
});

test('archived or non-pending new tasks are silent', () => {
  assert.deepEqual(planTaskCreated({ assignedToUserId: KID, archived: true }, PARENT), []);
  assert.deepEqual(planTaskCreated({ assignedToUserId: KID, status: 'approved' }, PARENT), []);
});

// --- Updated: assignment ------------------------------------------------------

test('parent assigning a pool task notifies the child', () => {
  const plans = planTaskUpdated({ assignedToUserId: null }, { assignedToUserId: KID }, PARENT);
  assert.deepEqual(plans, [{ kind: 'task_assigned', audience: { type: 'user', userId: KID }, excludeUserIds: [] }]);
});

test('parent reassigning to another child notifies the new child', () => {
  assert.deepEqual(kinds(planTaskUpdated({ assignedToUserId: KID }, { assignedToUserId: KID2 }, PARENT)), [
    'task_assigned',
  ]);
});

test('child claiming a pool task notifies parents (accepted)', () => {
  const plans = planTaskUpdated({ assignedToUserId: null }, { assignedToUserId: KID, claimedBy: KID }, KID);
  assert.deepEqual(plans, [{ kind: 'task_accepted', audience: { type: 'parents' }, excludeUserIds: [KID] }]);
});

test('claim is detected via claimedBy when auth context is missing', () => {
  assert.deepEqual(
    kinds(planTaskUpdated({ assignedToUserId: null }, { assignedToUserId: KID, claimedBy: KID }, undefined)),
    ['task_accepted'],
  );
  // Reassigned by a parent back to a child who claimed it earlier: not a claim.
  assert.deepEqual(
    kinds(planTaskUpdated({ assignedToUserId: KID2, claimedBy: KID }, { assignedToUserId: KID, claimedBy: KID }, undefined)),
    ['task_assigned'],
  );
});

test('unassigning (back to pool) or unchanged assignee is silent', () => {
  assert.deepEqual(planTaskUpdated({ assignedToUserId: KID }, { assignedToUserId: null }, PARENT), []);
  assert.deepEqual(planTaskUpdated({ assignedToUserId: KID, title: 'a' }, { assignedToUserId: KID, title: 'b' }, PARENT), []);
});

// --- Updated: status -----------------------------------------------------------

test('child completing a task notifies parents', () => {
  const plans = planTaskUpdated(
    { assignedToUserId: KID, status: 'pending' },
    { assignedToUserId: KID, status: 'completed' },
    KID,
  );
  assert.deepEqual(plans, [{ kind: 'task_completed', audience: { type: 'parents' }, excludeUserIds: [KID] }]);
});

test('parent approving notifies the assigned child', () => {
  const plans = planTaskUpdated(
    { assignedToUserId: KID, status: 'completed' },
    { assignedToUserId: KID, status: 'approved' },
    PARENT,
  );
  assert.deepEqual(plans, [{ kind: 'task_approved', audience: { type: 'user', userId: KID }, excludeUserIds: [] }]);
});

test('approving an unassigned task is silent', () => {
  assert.deepEqual(planTaskUpdated({ status: 'completed' }, { status: 'approved' }, PARENT), []);
});

test('un-completing (completed -> pending) is silent', () => {
  assert.deepEqual(
    planTaskUpdated({ assignedToUserId: KID, status: 'completed' }, { assignedToUserId: KID, status: 'pending' }, KID),
    [],
  );
});

test('archived tasks are silent', () => {
  assert.deepEqual(planTaskUpdated({ assignedToUserId: null }, { assignedToUserId: KID, archived: true }, PARENT), []);
});

test('writing the due-reminder log does not trigger anything', () => {
  const t: TaskData = { assignedToUserId: KID, status: 'pending', dueDate: new Date(0) };
  assert.deepEqual(planTaskUpdated(t, { ...t }, undefined), []);
});

// --- Redemption ---------------------------------------------------------------

test('redemption notifies parents', () => {
  assert.deepEqual(planRedemptionCreated(KID), [
    { kind: 'reward_redeemed', audience: { type: 'parents' }, excludeUserIds: [KID] },
  ]);
});

// --- Due / overdue -------------------------------------------------------------

const due = new Date('2026-10-05T06:00:00Z'); // local midnight in America/Denver
const at = (offsetMs: number) => new Date(due.getTime() + offsetMs);
const base: TaskData = { assignedToUserId: KID, status: 'pending', dueDate: due };

test('no reminder before the due-day reminder time', () => {
  assert.equal(planDueReminder(base, at(DUE_REMINDER_OFFSET_MS - 1)), null);
});

test('due reminder once on the due day', () => {
  assert.equal(planDueReminder(base, at(DUE_REMINDER_OFFSET_MS)), 'task_due');
  assert.equal(planDueReminder(base, at(DUE_REMINDER_OFFSET_MS), { dueFor: due.getTime() }), null);
});

test('overdue notice once the next morning', () => {
  assert.equal(planDueReminder(base, at(OVERDUE_OFFSET_MS)), 'task_overdue');
  assert.equal(planDueReminder(base, at(OVERDUE_OFFSET_MS), { dueFor: due.getTime() }), 'task_overdue');
  assert.equal(planDueReminder(base, at(OVERDUE_OFFSET_MS), { overdueFor: due.getTime() }), null);
});

test('stale overdue notices are skipped', () => {
  assert.equal(planDueReminder(base, at(OVERDUE_OFFSET_MS + LATE_GRACE_MS + 1)), null);
});

test('moving the due date re-arms reminders', () => {
  const old = due.getTime() - 7 * 24 * 3600 * 1000;
  assert.equal(planDueReminder(base, at(DUE_REMINDER_OFFSET_MS), { dueFor: old, overdueFor: old }), 'task_due');
});

test('no reminders for completed, unassigned, archived or undated tasks', () => {
  const now = at(DUE_REMINDER_OFFSET_MS);
  assert.equal(planDueReminder({ ...base, status: 'completed' }, now), null);
  assert.equal(planDueReminder({ ...base, assignedToUserId: null }, now), null);
  assert.equal(planDueReminder({ ...base, archived: true }, now), null);
  assert.equal(planDueReminder({ ...base, dueDate: null }, now), null);
});

test('sweep window covers every task that could need a reminder', () => {
  const now = at(OVERDUE_OFFSET_MS);
  const { from, to } = dueSweepWindow(now);
  assert.ok(from.getTime() <= due.getTime() && due.getTime() <= to.getTime());
  // Just-due and about-to-expire edges.
  assert.ok(dueSweepWindow(at(DUE_REMINDER_OFFSET_MS)).to.getTime() >= due.getTime());
  assert.ok(dueSweepWindow(at(OVERDUE_OFFSET_MS + LATE_GRACE_MS)).from.getTime() <= due.getTime());
});

// --- Copy ----------------------------------------------------------------------

test('message copy mentions names, task and rewards', () => {
  const ctx = { taskTitle: 'Feed the Dog', rewardXp: 15, coinReward: 5, actorName: 'Mom', childName: 'Sam' };
  assert.equal(buildMessage('task_assigned', ctx).body, 'Mom gave you "Feed the Dog" (+15 XP, +5 coins).');
  assert.equal(buildMessage('task_approved', ctx).body, '"Feed the Dog" was approved — you earned +15 XP and +5 coins!');
  assert.equal(buildMessage('task_completed', ctx).title, 'Sam completed a task ✅');
  assert.equal(
    buildMessage('reward_redeemed', { childName: 'Sam', rewardTitle: 'Game Time', rewardIcon: '🎮', coinCost: 100 }).body,
    '🎮 Game Time for 100 coins.',
  );
  const all: NotificationKind[] = [
    'task_available', 'task_assigned', 'task_due', 'task_overdue', 'task_approved',
    'task_accepted', 'task_completed', 'reward_redeemed',
  ];
  for (const k of all) {
    const m = buildMessage(k, {});
    assert.ok(m.title.length > 0 && m.body.length > 0, k);
  }
});
