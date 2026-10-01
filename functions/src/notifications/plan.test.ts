import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildMessage } from './messages';
import {
  planDigest,
  planMorning,
  planRedemptionCreated,
  planTaskCreated,
  planTaskUpdated,
  type MorningTask,
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

test('generated occurrences of repeating tasks are silent (the morning digest covers them)', () => {
  assert.deepEqual(planTaskCreated({ assignedToUserId: KID, scheduleId: 's1' }, undefined), []);
  assert.deepEqual(planTaskCreated({ assignedToUserId: null, scheduleId: 's1' }, undefined), []);
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

test('archiving a missed occurrence does not trigger anything', () => {
  const t: TaskData = { assignedToUserId: KID, status: 'pending', dueDate: new Date(0), scheduleId: 's1' };
  assert.deepEqual(planTaskUpdated(t, { ...t, archived: true }, undefined), []);
});

// --- Redemption ---------------------------------------------------------------

test('redemption notifies parents', () => {
  assert.deepEqual(planRedemptionCreated(KID), [
    { kind: 'reward_redeemed', audience: { type: 'parents' }, excludeUserIds: [KID] },
  ]);
});

// --- Morning run -----------------------------------------------------------------

const TODAY = '2026-10-05';
const YESTERDAY = '2026-10-04';
const mt = (id: string, day: string, extra: Partial<MorningTask> = {}): MorningTask => ({
  id, title: id, assignedToUserId: KID, status: 'pending', day, ...extra,
});

test('morning plan buckets due, overdue, pool and missed occurrences', () => {
  const plan = planMorning(
    [
      mt('due', TODAY),
      mt('due2', TODAY, { assignedToUserId: KID2 }),
      mt('late', YESTERDAY),
      mt('pool', TODAY, { assignedToUserId: null }),
      mt('poolYesterday', YESTERDAY, { assignedToUserId: null }),
      mt('done', TODAY, { status: 'completed' }),
      mt('archived', TODAY, { archived: true }),
      mt('missed', '2026-10-02', { scheduleId: 's1' }),
      mt('oldOneOff', '2026-10-02'),
      mt('tomorrow', '2026-10-06'),
    ],
    TODAY,
    YESTERDAY,
  );
  assert.deepEqual(plan.children.get(KID)?.due.map((t) => t.id), ['due']);
  assert.deepEqual(plan.children.get(KID)?.overdue.map((t) => t.id), ['late']);
  assert.deepEqual(plan.children.get(KID2)?.due.map((t) => t.id), ['due2']);
  assert.deepEqual(plan.pool.map((t) => t.id), ['pool']);
  assert.deepEqual(plan.toArchive, ['missed']);
});

test('digest: nothing, one specific item, or one summary', () => {
  const none = { due: [], overdue: [], pool: [] };
  assert.equal(planDigest(none), null);
  assert.deepEqual(planDigest({ ...none, due: [mt('a', TODAY)] }), { kind: 'task_due', task: mt('a', TODAY) });
  assert.equal(planDigest({ ...none, overdue: [mt('a', YESTERDAY)] })?.kind, 'task_overdue');
  assert.equal(planDigest({ ...none, pool: [mt('p', TODAY)] })?.kind, 'task_available');
  assert.deepEqual(planDigest({ ...none, due: [mt('a', TODAY)], pool: [mt('p', TODAY)] }), { kind: 'daily_digest' });
});

test('digest copy summarizes each group', () => {
  const m = buildMessage('daily_digest', {
    digest: { due: ['Feed the Dog', 'Set the Table', 'Trash'], overdue: ['Read'], pool: ['Dishes', 'Laundry'] },
  });
  assert.equal(m.body, '3 quests due today: Feed the Dog, Set the Table and 1 more · 1 overdue from yesterday · 2 up for grabs.');
  assert.equal(buildMessage('daily_digest', { digest: { due: ['A', 'B'], overdue: [], pool: [] } }).body, '2 quests due today: A and B.');
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
    'task_accepted', 'task_completed', 'reward_redeemed', 'daily_digest',
  ];
  for (const k of all) {
    const m = buildMessage(k, {});
    assert.ok(m.title.length > 0 && m.body.length > 0, k);
  }
});
