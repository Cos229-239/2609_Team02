/**
 * Who may change a child's login (password or email) from inside the app.
 * Pure rules for ./manage.ts, kept separate so they're unit-tested.
 *
 * A parent may manage a child when they share a household and the parent
 * is either the admin of one of those shared households or the parent who
 * created the child's login. (Name, age and avatar are plain profile
 * fields: any parent in the child's active household may edit those
 * directly, see firestore.rules.)
 */
import type { HouseholdInfo, MemberInfo } from './plan';

export const MIN_PASSWORD_LENGTH = 6;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export interface ManageInput {
  actor: MemberInfo | undefined;
  child: MemberInfo | undefined;
  /** The child's households. */
  childHouseholds: HouseholdInfo[];
}

/** Null when allowed, otherwise the reason shown to the parent. */
export function manageForbidden({ actor, child, childHouseholds }: ManageInput): string | null {
  if (!actor || actor.role !== 'parent') return 'Only a parent can change a child\'s login.';
  if (!child || child.role !== 'child') return 'Only child accounts can be changed this way.';
  const shared = childHouseholds.filter((h) => h.memberIds.includes(actor.id));
  if (shared.length === 0) return `${child.name || 'This child'} isn't in your household.`;
  const isAdmin = shared.some((h) => h.ownerId === actor.id);
  if (!isAdmin && child.createdByParentId !== actor.id) {
    return `Ask your household's admin to change ${child.name || 'this child'}'s login.`;
  }
  return null;
}

export type ManageChange =
  | { kind: 'password'; password: string }
  | { kind: 'email'; email: string };

/** Validates the request body. Returns the change or an error message. */
export function parseChange(data: unknown): ManageChange | string {
  const d = (data ?? {}) as Record<string, unknown>;
  const hasPassword = typeof d.password === 'string';
  const hasEmail = typeof d.email === 'string';
  if (hasPassword === hasEmail) return 'Send either a new password or a new email.';
  if (hasPassword) {
    const password = d.password as string;
    if (password.length < MIN_PASSWORD_LENGTH) {
      return `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
    }
    if (password.length > 128) return 'Password is too long.';
    return { kind: 'password', password };
  }
  const email = (d.email as string).trim().toLowerCase();
  if (!EMAIL_PATTERN.test(email) || email.length > 254) return 'Please enter a valid email address.';
  return { kind: 'email', email };
}
