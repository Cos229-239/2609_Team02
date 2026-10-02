import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  addDays,
  isValidDay,
  isValidTimeZone,
  isoWeekday,
  localDay,
  nextLocalHour,
  occurrenceId,
  occurrencesBetween,
  occursOn,
  parseRule,
  startOfDay,
  zonedTime,
  type ScheduleRule,
} from './recurrence';

const CHI = 'America/Chicago';

// --- Days ----------------------------------------------------------------------

test('day arithmetic and weekdays', () => {
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
  assert.equal(addDays('2028-03-01', -1), '2028-02-29');
  assert.equal(isoWeekday('2026-10-05'), 1); // Monday
  assert.equal(isoWeekday('2026-10-04'), 7); // Sunday
  assert.equal(isoWeekday('1970-01-01'), 4); // Thursday
  assert.ok(isValidDay('2026-02-28'));
  assert.ok(!isValidDay('2026-02-30'));
  assert.ok(!isValidDay('2026-2-3'));
});

// --- Time zones ----------------------------------------------------------------

test('time zone validation', () => {
  assert.ok(isValidTimeZone(CHI));
  assert.ok(isValidTimeZone('Asia/Kolkata'));
  assert.ok(!isValidTimeZone('Mars/Olympus'));
  assert.ok(!isValidTimeZone(''));
  assert.ok(!isValidTimeZone(undefined));
});

test('local day of an instant depends on the zone', () => {
  const instant = new Date('2026-10-02T03:00:00Z');
  assert.equal(localDay(instant, 'UTC'), '2026-10-02');
  assert.equal(localDay(instant, CHI), '2026-10-01'); // 10 PM CDT
});

test('9 AM local in several zones, including DST and half-hour offsets', () => {
  assert.equal(zonedTime('2026-10-01', 9, CHI).toISOString(), '2026-10-01T14:00:00.000Z'); // CDT
  assert.equal(zonedTime('2026-12-01', 9, CHI).toISOString(), '2026-12-01T15:00:00.000Z'); // CST
  assert.equal(zonedTime('2026-10-01', 9, 'Asia/Kolkata').toISOString(), '2026-10-01T03:30:00.000Z');
  assert.equal(zonedTime('2026-10-01', 9, 'Pacific/Auckland').toISOString(), '2026-09-30T20:00:00.000Z');
  // DST change days.
  assert.equal(zonedTime('2026-03-08', 9, CHI).toISOString(), '2026-03-08T14:00:00.000Z');
  assert.equal(zonedTime('2026-11-01', 9, CHI).toISOString(), '2026-11-01T15:00:00.000Z');
});

test('start of day is local midnight', () => {
  assert.equal(startOfDay('2026-10-05', CHI).toISOString(), '2026-10-05T05:00:00.000Z');
  assert.equal(startOfDay('2026-10-05', 'UTC').toISOString(), '2026-10-05T00:00:00.000Z');
});

test('next 9 AM is today before 9, tomorrow from 9 on', () => {
  const before = new Date('2026-10-01T13:59:00Z'); // 8:59 CDT
  const at = new Date('2026-10-01T14:00:00Z'); // 9:00 CDT
  assert.equal(nextLocalHour(before, CHI).toISOString(), '2026-10-01T14:00:00.000Z');
  assert.equal(nextLocalHour(at, CHI).toISOString(), '2026-10-02T14:00:00.000Z');
  // Across the fall-back change the UTC hour shifts.
  assert.equal(nextLocalHour(new Date('2026-10-31T20:00:00Z'), CHI).toISOString(), '2026-11-01T15:00:00.000Z');
});

// --- Repeat rules --------------------------------------------------------------

const rule = (r: Partial<ScheduleRule>): ScheduleRule => ({ repeat: 'daily', startDate: '2026-10-05', ...r });

test('nothing occurs before the start date', () => {
  assert.ok(!occursOn(rule({}), '2026-10-04'));
  assert.ok(occursOn(rule({}), '2026-10-05'));
});

test('every other day counts from the start date', () => {
  const r = rule({ repeat: 'everyOtherDay' });
  assert.deepEqual(occurrencesBetween(r, null, '2026-10-10'), ['2026-10-05', '2026-10-07', '2026-10-09']);
});

test('weekly on chosen weekdays', () => {
  const r = rule({ repeat: 'weekly', weekdays: [1, 4] }); // Mon, Thu
  assert.deepEqual(occurrencesBetween(r, null, '2026-10-18'), ['2026-10-05', '2026-10-08', '2026-10-12', '2026-10-15']);
});

test('weekly with no weekdays uses the start day', () => {
  const r = rule({ repeat: 'weekly', weekdays: [], startDate: '2026-10-07' }); // Wed
  assert.deepEqual(occurrencesBetween(r, null, '2026-10-21'), ['2026-10-07', '2026-10-14', '2026-10-21']);
});

test('every other week alternates Monday-based weeks starting with the start week', () => {
  // Starts Wednesday; Tuesday that week is before the start so it's skipped.
  const r = rule({ repeat: 'everyOtherWeek', weekdays: [2, 5], startDate: '2026-10-07' });
  assert.deepEqual(occurrencesBetween(r, null, '2026-10-31'), ['2026-10-09', '2026-10-20', '2026-10-23']);
});

test('monthly keeps the start day, clamped to short months', () => {
  const r = rule({ repeat: 'monthly', startDate: '2026-01-31' });
  assert.deepEqual(occurrencesBetween(r, null, '2026-05-31'), [
    '2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31',
  ]);
});

test('occurrencesBetween excludes the lower bound', () => {
  assert.deepEqual(occurrencesBetween(rule({}), '2026-10-06', '2026-10-08'), ['2026-10-07', '2026-10-08']);
  assert.deepEqual(occurrencesBetween(rule({}), '2026-10-08', '2026-10-08'), []);
});

test('parseRule validates', () => {
  assert.deepEqual(parseRule({ repeat: 'weekly', weekdays: [1, 'x'], startDate: '2026-10-05' }), {
    repeat: 'weekly', weekdays: [1], startDate: '2026-10-05',
  });
  assert.equal(parseRule({ repeat: 'yearly', startDate: '2026-10-05' }), null);
  assert.equal(parseRule({ repeat: 'daily', startDate: '2026-13-01' }), null);
});

test('occurrence ids are deterministic', () => {
  assert.equal(occurrenceId('abc', '2026-10-05'), 'abc_20261005');
});
