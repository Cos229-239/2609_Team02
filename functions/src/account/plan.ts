/**
 * Pure rules for in-app account deletion (no Firestore I/O; unit tested in
 * plan.test.ts). The callable in ./delete.ts loads the data, asks
 * [planAccountDeletion] what to do, and carries it out.
 *
 * Rules (mirror "Leave household" in the app):
 * - A household the target is admin of, with another parent in it, blocks
 *   deletion until the admin role is handed over.
 * - A household the target is admin of with no other parent is deleted
 *   along with everything in it. Child accounts the target created that
 *   belong to no other (surviving) household are deleted with it.
 * - Any other household is just left (children's tasks, redemptions and
 *   repeating tasks there are deleted).
 * - Someone else may only delete a *child* account, and only as the admin of
 *   every household that child is in (or, if the child is in none, as the
 *   parent who created it).
 */

export interface HouseholdInfo {
  id: string;
  name: string;
  ownerId: string | null;
  memberIds: string[];
}

export interface MemberInfo {
  id: string;
  name: string;
  role: string;
  createdByParentId?: string | null;
}

export interface DeletionInput {
  actorId: string;
  targetId: string;
  /** Profiles of the target and of every member of the target's households. */
  members: Map<string, MemberInfo>;
  /** Every household (by id) that the target or any of those members is in. */
  householdsByUser: Map<string, HouseholdInfo[]>;
}

export interface Blocker {
  householdId: string;
  householdName: string;
  reason: string;
}

export interface DeletionPlan {
  /** Set when the actor isn't allowed to delete the target at all. */
  forbidden: string | null;
  blockers: Blocker[];
  /** Households removed entirely (with all subcollections). */
  deleteHouseholds: HouseholdInfo[];
  /** Households the target is only removed from. */
  leaveHouseholds: HouseholdInfo[];
  /** Accounts to delete: the target first, then children going with it. */
  deleteUserIds: string[];
}

export function planAccountDeletion(input: DeletionInput): DeletionPlan {
  const { actorId, targetId, members, householdsByUser } = input;
  const target = members.get(targetId);
  const households = householdsByUser.get(targetId) ?? [];
  const empty: DeletionPlan = {
    forbidden: null,
    blockers: [],
    deleteHouseholds: [],
    leaveHouseholds: [],
    deleteUserIds: [],
  };

  if (actorId !== targetId) {
    const actor = members.get(actorId);
    if (!target || target.role !== 'child') {
      return { ...empty, forbidden: 'Only child accounts can be deleted by someone else.' };
    }
    if (!actor || actor.role !== 'parent') {
      return { ...empty, forbidden: 'Only a parent can delete a child account.' };
    }
    const allOwned = households.length > 0
      ? households.every((h) => h.ownerId === actorId)
      : target.createdByParentId === actorId;
    if (!allOwned) {
      return {
        ...empty,
        forbidden:
          `${target.name} is also in a household you aren't the admin of. ` +
          'Remove them from your household instead.',
      };
    }
  }

  const plan: DeletionPlan = { ...empty, deleteUserIds: [targetId] };
  for (const h of households) {
    if (h.ownerId !== targetId) {
      plan.leaveHouseholds.push(h);
      continue;
    }
    const otherParents = h.memberIds.filter((id) => id !== targetId && members.get(id)?.role === 'parent');
    if (otherParents.length > 0) {
      plan.blockers.push({
        householdId: h.id,
        householdName: h.name,
        reason: `Make another parent the admin of ${h.name} first.`,
      });
    } else {
      plan.deleteHouseholds.push(h);
    }
  }
  if (plan.blockers.length > 0) return plan;

  // Child accounts this parent created that would be left with no household.
  const doomed = new Set(plan.deleteHouseholds.map((h) => h.id));
  const candidates = new Set(plan.deleteHouseholds.flatMap((h) => h.memberIds));
  for (const id of candidates) {
    if (id === targetId) continue;
    const m = members.get(id);
    if (!m || m.role !== 'child' || m.createdByParentId !== targetId) continue;
    const theirs = householdsByUser.get(id) ?? [];
    if (theirs.every((h) => doomed.has(h.id))) plan.deleteUserIds.push(id);
  }
  return plan;
}

/** What the app shows before the user confirms (names only). */
export function summarize(plan: DeletionPlan, members: Map<string, MemberInfo>) {
  return {
    forbidden: plan.forbidden,
    blockers: plan.blockers.map((b) => b.reason),
    deletedHouseholds: plan.deleteHouseholds.map((h) => h.name),
    leftHouseholds: plan.leaveHouseholds.map((h) => h.name),
    deletedAccounts: plan.deleteUserIds.slice(1).map((id) => members.get(id)?.name ?? 'A child'),
  };
}
