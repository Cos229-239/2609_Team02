import { test } from 'node:test';
import assert from 'node:assert/strict';

import { planAccountDeletion, type HouseholdInfo, type MemberInfo } from './plan';

const pat: MemberInfo = { id: 'pat', name: 'Pat', role: 'parent' };
const sam: MemberInfo = { id: 'sam', name: 'Sam', role: 'parent' };
const ava: MemberInfo = { id: 'ava', name: 'Ava', role: 'child', createdByParentId: 'pat' };
const ben: MemberInfo = { id: 'ben', name: 'Ben', role: 'child' }; // signed up himself

const h = (id: string, ownerId: string, memberIds: string[]): HouseholdInfo => ({ id, name: id, ownerId, memberIds });

function input(actorId: string, targetId: string, households: HouseholdInfo[], people = [pat, sam, ava, ben]) {
  const members = new Map(people.map((p) => [p.id, p]));
  const householdsByUser = new Map<string, HouseholdInfo[]>();
  for (const p of people) householdsByUser.set(p.id, households.filter((x) => x.memberIds.includes(p.id)));
  return { actorId, targetId, members, householdsByUser };
}

test('admin with another parent in the household is blocked', () => {
  const plan = planAccountDeletion(input('pat', 'pat', [h('home', 'pat', ['pat', 'sam', 'ava'])]));
  assert.equal(plan.forbidden, null);
  assert.equal(plan.blockers.length, 1);
  assert.match(plan.blockers[0].reason, /another parent the admin/);
});

test('only parent: household and the children they created go with them', () => {
  const plan = planAccountDeletion(input('pat', 'pat', [h('home', 'pat', ['pat', 'ava', 'ben'])]));
  assert.deepEqual(plan.blockers, []);
  assert.deepEqual(plan.deleteHouseholds.map((x) => x.id), ['home']);
  // Ben signed up himself, so his account stays (with no household).
  assert.deepEqual(plan.deleteUserIds, ['pat', 'ava']);
});

test('a created child who is also in another household is kept', () => {
  const plan = planAccountDeletion(
    input('pat', 'pat', [h('home', 'pat', ['pat', 'ava']), h('grandma', 'sam', ['sam', 'ava'])]),
  );
  assert.deepEqual(plan.deleteUserIds, ['pat']);
});

test('non-admin parent just leaves', () => {
  const plan = planAccountDeletion(input('sam', 'sam', [h('home', 'pat', ['pat', 'sam'])]));
  assert.deepEqual(plan.leaveHouseholds.map((x) => x.id), ['home']);
  assert.deepEqual(plan.deleteHouseholds, []);
  assert.deepEqual(plan.deleteUserIds, ['sam']);
});

test('admin deletes a child in their household', () => {
  const plan = planAccountDeletion(input('pat', 'ava', [h('home', 'pat', ['pat', 'ava'])]));
  assert.equal(plan.forbidden, null);
  assert.deepEqual(plan.leaveHouseholds.map((x) => x.id), ['home']);
  assert.deepEqual(plan.deleteUserIds, ['ava']);
});

test("can't delete a child who is also in someone else's household", () => {
  const plan = planAccountDeletion(
    input('pat', 'ava', [h('home', 'pat', ['pat', 'ava']), h('grandma', 'sam', ['sam', 'ava'])]),
  );
  assert.match(plan.forbidden ?? '', /Remove them from your household/);
});

test('non-admin parent cannot delete a child', () => {
  const plan = planAccountDeletion(input('sam', 'ava', [h('home', 'pat', ['pat', 'sam', 'ava'])]));
  assert.ok(plan.forbidden);
});

test('nobody can delete another parent', () => {
  const plan = planAccountDeletion(input('pat', 'sam', [h('home', 'pat', ['pat', 'sam'])]));
  assert.ok(plan.forbidden);
});

test('child with no household can be deleted by the parent who created it', () => {
  assert.equal(planAccountDeletion(input('pat', 'ava', [])).forbidden, null);
  assert.ok(planAccountDeletion(input('sam', 'ava', [])).forbidden);
});

test('a child can delete their own account', () => {
  const plan = planAccountDeletion(input('ben', 'ben', [h('home', 'pat', ['pat', 'ben'])]));
  assert.equal(plan.forbidden, null);
  assert.deepEqual(plan.deleteUserIds, ['ben']);
});
