/**
 * Calendar math for repeating tasks and per-household morning runs.
 *
 * Days are plain local calendar dates ('YYYY-MM-DD') in the household's
 * time zone, so "every Monday" or "the 31st" never drifts with DST or with
 * where the server runs. Converting between a local day/hour and a real
 * instant uses the IANA zone via Intl (built into Node, no dependencies).
 *
 * Pure functions only — unit tested in recurrence.test.ts.
 */

export type Repeat = 'daily' | 'everyOtherDay' | 'weekly' | 'everyOtherWeek' | 'monthly';

export const REPEATS: readonly Repeat[] = ['daily', 'everyOtherDay', 'weekly', 'everyOtherWeek', 'monthly'];

/** The parts of a `households/{id}/taskSchedules/{id}` doc that decide when it occurs. */
export interface ScheduleRule {
  repeat: Repeat;
  /** ISO weekdays, 1 = Monday … 7 = Sunday. Used by weekly / everyOtherWeek. */
  weekdays?: number[];
  /** First day it can occur, 'YYYY-MM-DD' in the household's zone. */
  startDate: string;
}

export const DEFAULT_TIME_ZONE = 'UTC';
/** Local hour of the morning run (reminders + generating occurrences). */
export const MORNING_HOUR = 9;

// --- Local days ----------------------------------------------------------------

const DAY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const DAY_MS = 24 * 60 * 60 * 1000;

/** 'YYYY-MM-DD' → days since 1970-01-01. Throws on malformed input. */
export function dayNumber(day: string): number {
  const m = DAY_RE.exec(day);
  if (!m) throw new Error(`Bad day: ${day}`);
  return Math.round(Date.UTC(+m[1], +m[2] - 1, +m[3]) / DAY_MS);
}

/** Days since 1970-01-01 → 'YYYY-MM-DD'. */
export function dayString(n: number): string {
  return new Date(n * DAY_MS).toISOString().slice(0, 10);
}

export const addDays = (day: string, n: number): string => dayString(dayNumber(day) + n);

export function isValidDay(day: unknown): day is string {
  if (typeof day !== 'string' || !DAY_RE.test(day)) return false;
  return dayString(dayNumber(day)) === day; // rejects 2026-02-30 etc.
}

/** ISO weekday of a day: 1 = Monday … 7 = Sunday. */
export function isoWeekday(day: string): number {
  // 1970-01-01 was a Thursday (4).
  return ((((dayNumber(day) + 3) % 7) + 7) % 7) + 1;
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

// --- Time zones ----------------------------------------------------------------

export function isValidTimeZone(tz: unknown): tz is string {
  if (typeof tz !== 'string' || tz.length === 0) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

const formatters = new Map<string, Intl.DateTimeFormat>();
function formatter(tz: string): Intl.DateTimeFormat {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    formatters.set(tz, f);
  }
  return f;
}

function wallClock(instant: Date, tz: string) {
  const parts: Record<string, number> = {};
  for (const p of formatter(tz).formatToParts(instant)) {
    if (p.type !== 'literal') parts[p.type] = Number(p.value);
  }
  return parts as { year: number; month: number; day: number; hour: number; minute: number; second: number };
}

/** The local calendar day an instant falls on in [tz]. */
export function localDay(instant: Date, tz: string): string {
  const w = wallClock(instant, tz);
  return dayString(Math.round(Date.UTC(w.year, w.month - 1, w.day) / DAY_MS));
}

/** How far [tz]'s wall clock is ahead of UTC at [instant], in ms. */
function offsetMs(instant: number, tz: string): number {
  const w = wallClock(new Date(instant), tz);
  const asUtc = Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);
  return asUtc - Math.floor(instant / 1000) * 1000;
}

/**
 * The instant at which it is [hour]:00 on [day] in [tz]. If that wall time
 * doesn't exist (skipped by a DST jump) the result lands just after the gap.
 */
export function zonedTime(day: string, hour: number, tz: string): Date {
  const guess = dayNumber(day) * DAY_MS + hour * 60 * 60 * 1000;
  const first = guess - offsetMs(guess, tz);
  const second = guess - offsetMs(first, tz);
  return new Date(second);
}

/** Local midnight that starts [day] in [tz] — what tasks store as `dueDate`. */
export const startOfDay = (day: string, tz: string): Date => zonedTime(day, 0, tz);

/** The next [hour]:00 local time in [tz] strictly after [now]. */
export function nextLocalHour(now: Date, tz: string, hour = MORNING_HOUR): Date {
  const today = localDay(now, tz);
  const candidate = zonedTime(today, hour, tz);
  return candidate.getTime() > now.getTime() ? candidate : zonedTime(addDays(today, 1), hour, tz);
}

// --- Repeat rules --------------------------------------------------------------

/** Normalizes stored weekdays; weekly rules with none fall back to the start day. */
export function ruleWeekdays(rule: ScheduleRule): number[] {
  const days = [...new Set((rule.weekdays ?? []).filter((d) => Number.isInteger(d) && d >= 1 && d <= 7))].sort((a, b) => a - b);
  return days.length > 0 ? days : [isoWeekday(rule.startDate)];
}

/** Does [rule] produce an occurrence on [day]? */
export function occursOn(rule: ScheduleRule, day: string): boolean {
  const start = dayNumber(rule.startDate);
  const n = dayNumber(day);
  if (n < start) return false;

  switch (rule.repeat) {
    case 'daily':
      return true;
    case 'everyOtherDay':
      return (n - start) % 2 === 0;
    case 'weekly':
      return ruleWeekdays(rule).includes(isoWeekday(day));
    case 'everyOtherWeek': {
      if (!ruleWeekdays(rule).includes(isoWeekday(day))) return false;
      // Weeks run Monday–Sunday; the start date's week is "on".
      const weekOf = (d: number, iso: string) => d - (isoWeekday(iso) - 1);
      const weeks = (weekOf(n, day) - weekOf(start, rule.startDate)) / 7;
      return weeks % 2 === 0;
    }
    case 'monthly': {
      // Same day of month as the start; short months use their last day.
      const [y, m, d] = day.split('-').map(Number);
      const startDom = Number(rule.startDate.slice(8, 10));
      return d === Math.min(startDom, daysInMonth(y, m));
    }
    default:
      return false;
  }
}

/** Every day in (after, through] on which [rule] occurs. `after` null = no lower bound but the start. */
export function occurrencesBetween(rule: ScheduleRule, after: string | null, through: string): string[] {
  const out: string[] = [];
  const from = Math.max(dayNumber(rule.startDate), after ? dayNumber(after) + 1 : -Infinity);
  for (let n = from; n <= dayNumber(through); n++) {
    const day = dayString(n);
    if (occursOn(rule, day)) out.push(day);
  }
  return out;
}

/** Validates a schedule doc's rule fields; null if unusable. */
export function parseRule(data: { repeat?: unknown; weekdays?: unknown; startDate?: unknown }): ScheduleRule | null {
  if (!REPEATS.includes(data.repeat as Repeat) || !isValidDay(data.startDate)) return null;
  const weekdays = Array.isArray(data.weekdays) ? data.weekdays.filter((d): d is number => typeof d === 'number') : [];
  return { repeat: data.repeat as Repeat, weekdays, startDate: data.startDate };
}

/** Task doc id for one occurrence — deterministic, so generating is idempotent. */
export const occurrenceId = (scheduleId: string, day: string): string => `${scheduleId}_${day.replace(/-/g, '')}`;
