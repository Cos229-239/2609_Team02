import { test } from 'node:test';
import assert from 'node:assert/strict';

import { manageForbidden, parseChange } from './manage-plan';
import type { HouseholdInfo, MemberInfo } from './plan';

const pat: MemberInfo = { id: 'pat', name: 'Pat', role: 'parent' };
const sam: MemberInfo = { id: 'sam', name: 'Sam', role: 'parent' };
const eve: MemberInfo = { id: 'eve', name: 'Eve', role: 'parent' };
const ava: MemberInfo = { id: 'ava', name: 'Ava', role: 'child', createdByParentId: 'pat' };
const ben: MemberInfo = { id: 'ben', name: 'Ben', role: 'child' };

const home: HouseholdInfo = { id: 'home', name: 'Home', ownerId: 'pat', memberIds: ['pat', 'sam', 'ava', 'ben'] };

test('admin may manage any child in their household', () => {
  assert.equal(manageForbidden({ actor: pat, child: ben, childHouseholds: [home] }), null);
  assert.equal(manageForbidden({ actor: pat, child: ava, childHouseholds: [home] }), null);
});

test('non-admin parent may manage a child they created, not others', () => {
  const samsKid: MemberInfo = { ...ben, createdByParentId: 'sam' };
  assert.equal(manageForbidden({ actor: sam, child: samsKid, childHouseholds: [home] }), null);
  assert.match(manageForbidden({ actor: sam, child: ava, childHouseholds: [home] })!, /admin/);
});

test('a parent outside the household is refused, even the creator', () => {
  assert.match(manageForbidden({ actor: eve, child: ava, childHouseholds: [home] })!, /isn't in your household/);
  const gone: MemberInfo = { ...ava, createdByParentId: 'eve' };
  assert.match(manageForbidden({ actor: eve, child: gone, childHouseholds: [home] })!, /isn't in your household/);
});

test('children and parents as targets', () => {
  assert.match(manageForbidden({ actor: ava, child: ben, childHouseholds: [home] })!, /Only a parent/);
  assert.match(manageForbidden({ actor: pat, child: sam, childHouseholds: [home] })!, /Only child accounts/);
  assert.match(manageForbidden({ actor: pat, child: undefined, childHouseholds: [] })!, /Only child accounts/);
});

test('parseChange validates the body', () => {
  assert.deepEqual(parseChange({ password: 'secret1' }), { kind: 'password', password: 'secret1' });
  assert.deepEqual(parseChange({ email: ' Mom+Ava@Example.com ' }), { kind: 'email', email: 'mom+ava@example.com' });
  assert.match(parseChange({ password: '123' }) as string, /at least 6/);
  assert.match(parseChange({ email: 'nope' }) as string, /valid email/);
  assert.match(parseChange({}) as string, /either/);
  assert.match(parseChange({ password: 'secret1', email: 'a@b.co' }) as string, /either/);
});
