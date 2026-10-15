# Family Milestones, Board Progression & Mini-Games

Design notes for the family milestone ("Family Goal") board and the four
reward mini-games. Read this before changing anything under
`lib/features/milestones/`, `lib/features/minigames/`,
`lib/core/services/milestone_service.dart`,
`lib/core/services/mini_game_service.dart` or `functions/src/minigames/`.

## 1. What already existed (and what we reuse)

| Existing piece | How this feature uses it |
|---|---|
| `DatabaseService._finishTask` — the one transaction that moves a task to `approved` and pays XP/coins | Extended: the same transaction now also records the milestone contribution, moves the board, writes the progress event and offers the mini-game session. One commit, so approval, board and bonus offer can never disagree. |
| `TaskModel` (occurrence ids `{scheduleId}_{YYYYMMDD}` for repeating tasks) | The task occurrence id is the idempotency key for everything below. |
| `Goal` / `GoalService` (daily/weekly metric goals) | Left untouched and still fed after approval. A milestone is a different thing (board, deadline, shared reward, status lifecycle), so it gets its own model rather than overloading `GoalPeriod`. |
| Reward store (`Reward`, Rewards tab) | Gains a **Mini-Games** section (casual play). Redemption is unchanged. |
| Notifications (`functions/src/notifications`) | New kind `milestone_completed`, sent through the existing planner/dispatcher with `claimEvent` de-duplication. |
| Household membership (`memberIds`), roles, `firestore.rules` helpers | All new collections are household subcollections and reuse `isMemberOf` / `isParent`. |
| Cloud Functions (TypeScript, pure `plan.ts` + I/O `index.ts`, `node --test`) | The XP bonus is awarded by a Firestore trigger in `functions/src/minigames/`, following the same split. |

## 2. Data model

All paths are under `households/{householdId}`.

### `milestones/{milestoneId}` — the shared family goal
`title`, `description`, `illustration` (emoji), `rewardTitle`, `rewardIcon`,
`startsAt`, `endsAt` (exclusive), `boardLength` (5–60 spaces),
`spacesPerTask` (1–3), `eligibility` `{oneTimeTasks: bool, repeating:
'all'|'selected'|'none', scheduleIds: []}`, `participantIds` (empty = every
child), `status` (`active|paused|completed|cancelled`), `position`,
`createdBy`, `createdAt`, `completedAt`, `rewardClaimedAt`,
`rewardClaimedBy`, `endedReason`.

`upcoming` and `expired` are **derived**, not stored: `upcoming` = active and
`now < startsAt`; `expired` = active/paused, not completed and
`now >= endsAt`. That keeps a deadline passing from needing a write.

Only one milestone is *current* (stored status `active` or `paused`). The
editor refuses to create a second one; a parent extends, restarts or replaces
the current one instead. If two parents somehow both create one, contributions
go to the most recently created active milestone.

### `milestones/{milestoneId}/contributions/{taskId}` — audit trail
`childId`, `taskId`, `taskTitle`, `scheduleId`, `spaces` (actually applied),
`fromPosition`, `toPosition`, `completedAt`, `approvedAt`, `approvedBy`.
Document id = task occurrence id, so a task can contribute at most once.
Create-only (no updates/deletes from clients), so progress can always be
recalculated as `min(boardLength, Σ spaces)` (parent action **Recalculate**).

### `progressEvents/{taskId}` — "show this approval to the child once"
`childId`, `taskId`, `taskTitle`, `baseXp`, `createdAt`, optional
`milestoneId`/`milestoneTitle`/`fromPosition`/`toPosition`/`boardLength`,
`milestoneCompleted`, optional `miniGameSessionId`, `presentedAt` (null until
shown). The child app presents unpresented events once, then sets
`presentedAt` (the only field a child may change) — so duplicate snapshots,
restarts and second devices don't replay the animation.

### `miniGameSessions/{taskId}` — one rewarded game per approval
`childId`, `taskId`, `taskTitle`, `gameId`, `seed`, `baseXp`, `settings`
(resolved snapshot: game settings + multiplier bounds), `status`, `attempts`,
`createdAt`, `expiresAt`, `startedAt`, `finishedAt`, `outcome`; server-only:
`multiplierPct`, `bonusXp`, `finalXp`, `rewardedAt`, `rejectReason`.

Lifecycle: `offered → started → finished → rewarded|rejected`, or
`offered|started → skipped`. A session that was started but interrupted can
be started again once (`attempts ≤ 2`) until `expiresAt` (3 days). Skipping or
leaving keeps the task's base XP; only the bonus is lost.

### `xpTransactions/{id}` — server-written XP ledger for bonuses
`childId`, `source: 'miniGame'`, `sessionId`, `taskId`, `gameId`, `baseXp`,
`multiplierPct`, `bonusXp`, `finalXp`, `performance`, `createdAt`. Id
`minigame_{taskId}`; created with `create()` inside the award transaction, so
a bonus exists at most once.

### `miniGameSettings/household` and `miniGameSettings/{childId}`
Household defaults and per-child overrides (partial). Resolution:
built-in defaults ← household doc ← child doc, every field clamped to its safe
range; malformed values fall back to the default. The resolved settings are
**snapshotted into the session** when it is offered, so later changes never
alter a session in progress.

## 3. Contribution rules

A task approval contributes to the current milestone when **all** hold:

1. The task is assigned to a child (`assignedToUserId`) who is a household
   member and in `participantIds` (or `participantIds` is empty).
2. The milestone's stored status is `active` (paused/completed/cancelled
   milestones never move).
3. Time window: the task was completed (`completedAt`, or the approval time
   for parent-completed tasks) in `[startsAt, endsAt)`, **and** it is approved
   no later than `endsAt + 48h` (so a chore done on the last day and approved
   the next morning still counts).
4. Eligibility: one-time tasks need `oneTimeTasks`; repeating occurrences need
   `repeating == 'all'`, or `'selected'` with the occurrence's `scheduleId`
   listed.
5. No contribution document exists yet for this task id.

Each contribution moves the board `spacesPerTask` spaces, capped at
`boardLength` (no overflow). Reaching `boardLength` sets `status: completed`
and `completedAt` in the same transaction.

**Date boundaries / time zones.** The editor turns the chosen start and
deadline *days* into instants using the creating parent's device calendar
(`startsAt` = local midnight of the start day, `endsAt` = local midnight after
the deadline day). Households' `timezone` is itself set from a member's
device, so for the normal case these are the household's local days. All
later comparisons use those stored instants, so every device and the server
agree regardless of their own zones.

**Concurrency.** The milestone document is read inside the approval
transaction, so two parents approving at once are serialised by Firestore
(the loser retries and sees the new position and the existing contribution).

## 4. Board

`BoardLayout` (pure) places `boardLength + 1` spaces (0 = Start) on a
serpentine path sized to the available width. `FamilyBoard` paints a grassy
background, the winding path, numbered spaces, a Start flag, the reward
illustration at the finish, and the family token (👨‍👩‍👧). Movement animates one
hop per space. The shown position always comes from Firestore, so restarts
and other devices show the same place.

Entry points: a **Family Goal** card on both Home screens (opens the board),
the approval journey (below), and the celebration screen.

**Approval journey (child).** `ProgressEventPresenter` watches the signed-in
child's unpresented `progressEvents` in the active household. When the main
tabs are on screen it pushes `ApprovalJourneyScreen` once for the batch:
"Task approved!" → board animates from the earliest `fromPosition` to the
latest `toPosition` → celebration if the milestone completed → the first
offered bonus game (if any) → result → back to Home. Every event in the batch
is marked presented when the journey opens. Bonus games that weren't played
stay on Home as "Bonus game waiting" until they expire.

## 5. Mini-game framework

```
MiniGameId                      enum: the four games (title, emoji, blurb)
MiniGameDefinition              builds the game widget for a MiniGamePlayContext
MiniGameRegistry                id → definition (each game branch registers one)
MiniGamePlayContext             resolved settings, seeded Random, onFinished
MiniGameOutcome                 details + performance (0..1) + elapsed
GameSelector                    weighted, injectable Random
XpMultiplier                    performance → multiplier → XP (central)
MiniGameService                 sessions: start / finish / skip, settings I/O
MiniGameHostScreen              intro → game → result, exit/confirm, casual vs rewarded
```

**Random selection.** At approval the parent's client picks a game with
`GameSelector` over the child's resolved `gameWeights` (default 1 each = fair)
using an injectable `Random`, and stores `gameId` and a `seed` on the session,
so restarts never re-roll and tests are deterministic.

**XP rule (single source of truth).** Each game reports a performance
`p ∈ [0, 1]`. Then

```
curve(p)      = p^0.7 (gentle) | p (balanced, default) | p^1.5 (challenging)
multiplierPct = roundTo5(minPct + (maxPct − minPct) · curve(p))   // 100..300
finalXp       = (baseXp · multiplierPct + 50) ÷ 100   (integer, half-up)
bonusXp       = finalXp − baseXp
```

Defaults: `minPct 100`, `maxPct 200`, balanced. Example: 20 base XP and
1.5× → 30 XP final, +10 bonus. Only the qualifying task's XP is multiplied —
never coins, milestone spaces, household rewards or other XP. Implemented
identically in `lib/features/minigames/core/xp_multiplier.dart` (preview) and
`functions/src/minigames/plan.ts` (authority); both have tests on the same
table of cases.

**Performance per game**

| Game | `p` |
|---|---|
| Balloon Popper | balloons popped ÷ target |
| Match Pairs | pairs matched ÷ total pairs (game ends after `maxMisses` misses, default 3) |
| Jump and Run | 0.7 · distance fraction + 0.3 · collectibles fraction |
| Memory Run | longest sequence repeated ÷ target length (target ≤ 25) |

Every game is normalised to the same `p`, so a 25-step Memory Run can't earn
more than a perfect Balloon Popper.

**Trust.** The child's app only writes `status: finished`, its `outcome` and
`finishedAt == request.time` (rules). The `awardMiniGameBonus` trigger then,
in one transaction: re-reads the session (must still be `finished`), re-reads
the task (must be approved and assigned to the session's child) and takes the
base XP from the task, validates the outcome against the snapshotted settings
(counts within bounds, plausible minimum play time from the server-stamped
`startedAt`/`finishedAt`), recomputes `p` and the multiplier itself (clamped to
100–300 %), creates `xpTransactions/minigame_{taskId}`, increments the child's
XP by the bonus, and marks the session `rewarded`. Anything off → `rejected`
with a reason; nothing is paid.

Limitation (documented, accepted): a modified app could still report a
perfect-but-plausible outcome. The damage is bounded to one task's XP ×
`maxPct`, once per approved task, which a parent set. Firestore rules were also
tightened so a child can no longer raise their own `xp`/`coins` directly.

**Casual play** (Reward Store → Mini-Games) runs the same games with the
child's resolved settings and a fresh seed, entirely on the device. Nothing is
written and the result screen says it's practice — no XP, no coins.

## 6. Security rules summary

| Collection | Read | Write |
|---|---|---|
| `milestones`, `contributions` | members | parents (contributions create-only) |
| `progressEvents` | members | parents create; the child may set its own `presentedAt` only |
| `miniGameSessions` | members | parents create; the child may move its own session `offered→started→finished` / `→skipped` with `request.time` timestamps; server-only reward fields |
| `xpTransactions` | members | server only |
| `miniGameSettings` | members | parents |
| `users/{uid}` | unchanged | self-updates may not raise `xp`/`coins` (children); profiles are created with 0 XP/coins |

## 7. Branches

| Branch | Content |
|---|---|
| `features/family-milestone-board` | integration: milestones, board, framework, settings, store, functions, rules |
| `features/minigame-balloon-popper` | Game A |
| `features/minigame-match-pairs` | Game B |
| `features/minigame-jump-and-run` | Game C |
| `features/minigame-memory-run` | Game D |

Game branches start from the integration branch after the framework landed and
are merged back with `--no-ff`. The integration branch targets `dev`.

## 8. Deploying

```bash
firebase deploy --only firestore:rules,functions
```

Without the `awardMiniGameBonus` function deployed, finished games stay
"Bonus on its way" and no bonus is paid (base XP is unaffected).
