# Family Challenges & Goals

## Overview

Family Challenges & Goals adds individual and cooperative goals to Famotive. Goals allow children and household members to work toward measurable Famotive activity targets while tracking overall progress and individual contributions.

This feature is designed as a cooperative progression system.

Competitive functionality such as household rankings, leaderboards, sibling-versus-sibling challenges, and winner determination belongs to the separate Household Competition feature and is outside the scope of this system.

## Feature Requirements

Family Challenges & Goals supports:

- Individual daily and weekly goals.
- Family-wide goals that eligible household members can contribute toward.
- Team goals involving selected household members.
- Goals based on measurable Famotive activity.
- Individual contribution tracking for shared goals.
- Overall goal progress tracking.
- Goal completion detection.
- Duplicate activity prevention.
- Persistent goal and contribution data.
- Active goal and progress display.
- Goal completion feedback.

Initial supported activity metrics are:

- Tasks completed
- XP earned
- Coins earned

The goal architecture should allow additional Famotive activity metrics to be added later without redesigning the goal system.

---

## Architecture Principles

### Household-Scoped Goals

Goals belong to a household.

Famotive's multi-household architecture uses:

```text
households/{householdId}
```

as the ownership boundary for household-specific data such as tasks, task schedules, rewards, and redemptions.

Goals follow the same structure:

```text
households/{householdId}/goals/{goalId}
```

Because the Firestore document path establishes household ownership, the goal document does not need to duplicate `householdId`.

Household membership continues to use:

```text
households/{householdId}.memberIds
```

as the source of truth.

`users/{uid}.householdId` represents the user's currently active household and must not be treated as the source of truth for household membership.

### Global Progression vs. Household Goal Progression

XP and Coins remain global user progression values:

```text
users/{uid}.xp
users/{uid}.coins
```

They carry with the user across households.

Goal progress is household-specific.

For example, if a child earns 50 XP from a task in Household A:

```text
User XP:
+50 globally

Household A XP Goal:
+50 if the activity qualifies

Household B XP Goal:
No change
```

A goal must therefore track qualifying activity that occurred within its household rather than deriving progress directly from the user's global XP or Coin balance.

---

## Goal Types

### Individual

An individual goal applies to one household member.

Example:

```text
Complete 5 tasks this week
Participant: Sally
Progress: 3 / 5
```

Individual goals support daily and weekly goal periods.

### Family

A family goal allows eligible household members to contribute toward one shared target.

Example:

```text
Complete 20 household tasks this week

Sally: 8
Billy: 4
Parent: 2

Overall: 14 / 20
```

Household membership determines the eligible family population unless additional restrictions are introduced later.

### Team

A team goal applies to a selected group of household members working toward one shared target.

Example:

```text
Sally + Billy complete 10 tasks this week

Sally: 4
Billy: 3

Overall: 7 / 10
```

Team goals therefore require explicit participant information.

---

## Goal Metrics

Goals use a metric to determine what qualifying activity contributes toward progress.

Initial metrics:

```dart
enum GoalMetric {
  tasksCompleted,
  xpEarned,
  coinsEarned,
}
```

The meaning of `targetValue` and `currentProgress` depends on the metric.

### Tasks Completed

```text
Target: 10
Current Progress: 6
```

Each qualifying approved task contributes:

```text
+1
```

### XP Earned

```text
Target: 500 XP
Current Progress: 350 XP
```

A qualifying approved task contributes its configured `rewardXp`.

### Coins Earned

```text
Target: 100 Coins
Current Progress: 65 Coins
```

A qualifying approved task contributes its configured `coinReward`.

Using a metric-based design prevents the goal model from requiring separate fields such as `targetTasks`, `targetXp`, and `targetCoins`.

Additional supported Famotive metrics can be introduced later by extending the metric definition and activity-processing logic.

---

## Goal Periods

Initial goal periods are:

```dart
enum GoalPeriod {
  daily,
  weekly,
}
```

Goals also store their actual start and end timestamps.

This allows the service to determine whether a goal is currently active and ensures activity only contributes during the appropriate goal period.

Households already contain an IANA `timezone`. Future daily and weekly period generation or rollover behavior should use the household timezone rather than relying solely on the device's local timezone.

Custom goal periods are not required by the current Family Challenges & Goals feature and are outside the initial implementation scope.

---

## Goal Model

The planned goal domain model contains:

```text
Goal
├── id
├── title
├── type
├── metric
├── period
├── targetValue
├── currentProgress
├── participantIds
├── startsAt
├── endsAt
└── completedAt
```

### Field Responsibilities

**id**

Firestore document identifier.

**title**

Human-readable description of the goal.

**type**

Determines whether the goal is individual, family-wide, or team-based.

**metric**

Determines which type of Famotive activity contributes toward progress.

**period**

Defines the daily or weekly goal period.

**targetValue**

The amount required to complete the goal.

**currentProgress**

Cached aggregate of qualifying contribution amounts.

This allows the UI to display progress without reading every contribution document.

**participantIds**

Defines explicitly applicable users where required.

Expected behavior:

```text
Individual:
Exactly one participant.

Team:
Selected household members.

Family:
Household membership determines eligibility.
```

**startsAt / endsAt**

Define the active goal window.

**completedAt**

Set when progress reaches the target.

A non-null `completedAt` identifies a completed goal.

The initial design does not require a large goal status enum. Active, completed, and expired/incomplete states can be derived from the goal's timestamps and `completedAt` where appropriate.

---

## Contribution Model

Shared goals must track each applicable user's contribution.

Contributions also provide an audit trail showing which Famotive activities produced goal progress.

Planned structure:

```text
GoalContribution
├── activityId
├── userId
├── amount
├── activityType
└── recordedAt
```

### activityId

Identifies the source Famotive activity.

For task-based goals, this is the task occurrence ID.

Repeating tasks use the individual task occurrence ID rather than the repeating schedule ID so separate occurrences can each contribute.

### userId

Identifies the household member responsible for the contribution.

### amount

Amount contributed toward the goal.

Examples:

```text
tasksCompleted -> 1
xpEarned       -> task.rewardXp
coinsEarned    -> task.coinReward
```

### activityType

Identifies the type of Famotive activity that generated the contribution.

Initial activity type:

```dart
enum GoalActivityType {
  taskApproval,
}
```

Additional activity types can be introduced if future Famotive features become valid goal activities.

### recordedAt

Timestamp indicating when the contribution was recorded.

---

## Firestore Structure

Planned Firestore structure:

```text
households/{householdId}
│
├── tasks/
├── taskSchedules/
├── rewards/
├── redemptions/
│
└── goals/
    │
    └── {goalId}
        ├── title
        ├── type
        ├── metric
        ├── period
        ├── targetValue
        ├── currentProgress
        ├── participantIds
        ├── startsAt
        ├── endsAt
        ├── completedAt
        │
        └── contributions/
            └── {activityId}
                ├── userId
                ├── amount
                ├── activityType
                └── recordedAt
```

This structure keeps goals isolated to the correct household and keeps contribution history associated with its goal.

---

## Duplicate Activity Prevention

Completed Famotive activity must not contribute more than once toward the same goal.

Contribution documents use the source activity ID as their logical identity:

```text
goals/{goalId}/contributions/{activityId}
```

Example:

```text
Goal: Complete 5 Tasks

Task A approved
-> contributions/taskA created
-> progress becomes 1 / 5

Task B approved
-> contributions/taskB created
-> progress becomes 2 / 5

Task B processed again
-> contributions/taskB already exists
-> progress remains 2 / 5
```

The same activity may legitimately contribute to different goals.

For example:

```text
Goal A: Complete 10 Tasks
└── contributions/task123 = +1

Goal B: Earn 500 XP
└── contributions/task123 = +50 XP
```

Because the contribution exists underneath a specific goal, `goalId + activityId` forms the logical duplicate-prevention boundary.

Contribution creation and aggregate progress updates should be performed transactionally so a contribution and its corresponding progress update cannot become inconsistent.

---

## Task Activity Integration

Famotive tasks use the following lifecycle:

```text
Pending
   ↓
Child completes task
   ↓
Completed / Awaiting Approval
   ↓
Parent approves task
   ↓
Approved
```

Task approval is the authoritative qualifying activity for initial goal integration.

The existing task approval process:

1. Verifies the task is awaiting approval.
2. Marks the task approved.
3. Records the approval timestamp.
4. Awards the assigned child XP.
5. Awards the assigned child Coins.

Family Challenges will integrate with approved activity rather than the child's initial completion action.

Conceptually:

```text
Task Approved
      │
      ├── Global user XP += rewardXp
      ├── Global user Coins += coinReward
      │
      └── Goal activity processing
              │
              ├── tasksCompleted -> +1
              ├── xpEarned       -> +rewardXp
              └── coinsEarned    -> +coinReward
```

Only active goals belonging to the task's household and applicable to the assigned user should be considered.

Production task integration is intentionally separated from the initial goal foundation implementation.

---

## Goal Completion

After a valid contribution is recorded:

```text
newProgress = currentProgress + contribution.amount
```

If:

```text
newProgress >= targetValue
```

the goal is completed and `completedAt` is recorded.

Progress may reach or exceed the target, but completion must only be identified once.

Example:

```text
Target: 500 XP
Current: 475 XP
Contribution: 50 XP

New Progress: 525 XP
Goal: Completed
```

The system must support both incomplete and completed goal states.

Goal completion feedback is a UI responsibility built on top of the persisted completion state.

The initial Family Challenges implementation does not automatically award additional XP or Coins when a goal is completed. Completion rewards are not defined by the current feature requirements and could introduce circular progression behavior for XP- or Coin-based goals.

---

## Goal Service

Goal-specific business logic should live in a dedicated service rather than expanding `DatabaseService` with all goal behavior.

Planned responsibility:

```text
GoalService
│
├── Goal persistence
├── Goal queries/listeners
├── Contribution persistence
├── Eligibility validation
├── Activity validation
├── Duplicate prevention
├── Progress updates
└── Completion detection
```

Conceptually, contribution processing performs:

```text
Receive activity
      ↓
Is goal active?
      ↓
Does the user qualify for this goal?
      ↓
Does the activity match the goal metric?
      ↓
Has this activity already contributed?
      ↓
Create contribution
      ↓
Update aggregate progress
      ↓
Target reached?
      ↓
Mark goal completed
```

Task lifecycle integration remains outside the core goal model and can call into `GoalService` when qualifying activity occurs.

---

## Security

Goal data is household-specific and should follow Famotive's existing household membership security model.

Household members may read applicable household goal information.

Goal creation and management should require:

```text
Authenticated user
        +
Household membership
        +
Parent role
```

This prevents a parent who is not a member of a household from managing that household's goals.

### Goal Progress Security Boundary

Goal configuration and goal progress are separate security concerns.

Goal creation and management should remain restricted to authenticated parent
members of the household. Children may read applicable goals but should not be
able to create or redefine goal configuration.

Goal progress and contribution records are updated by `GoalService`. During
PR1, Firestore rules enforce household isolation for these records using the
existing `isMemberOf(householdId)` authorization model.

These rules do not independently prove that a contribution originated from a
legitimate Famotive activity. In particular, Firestore security rules alone do
not verify that a contribution corresponds to an approved task or that its XP
or coin amount matches the task that produced it.

Authoritative task-to-goal activity generation will be addressed during PR2
when approved task activity is integrated with `GoalService`. Stronger
tamper-resistance may require moving activity-derived goal updates to trusted
server-side processing rather than relying exclusively on client-originated
Firestore writes.

Goal progress should not rely on arbitrary client modification of `currentProgress`. Progress changes should correspond to persisted qualifying contributions.

Exact Firestore write permissions may evolve as goal activity integration is implemented. The goal architecture should preserve the ability to move activity processing to trusted server-side logic in the future without changing the domain model.

---

## Testing Strategy

The feature should include automated coverage for the scenarios required by the Family Challenges & Goals Definition of Done.

### Goal Types

- Individual goals can be created and persisted.
- Family goals can be created and persisted.
- Team goals can be created and persisted.

### Individual Progress

- Applicable user activity updates progress.
- Non-applicable user activity does not update an individual goal.

### Shared Progress

Example:

```text
Target: 10 tasks

Sally contributes 3.
Billy contributes 2.

Sally contribution: 3
Billy contribution: 2
Overall progress: 5 / 10
```

### Supported Metrics

- Approved tasks update task-completion goals correctly.
- Task XP updates XP goals correctly.
- Task Coins update Coin goals correctly.

### Duplicate Prevention

- An activity contributes once.
- Processing the same activity again does not increase progress.

### Completion

- Progress below the target remains incomplete.
- Reaching the target marks the goal complete.
- Exceeding the target still marks the goal complete correctly.
- Completion information persists.

### Household Isolation

- Activity from Household A does not update Household B goals.
- Goal data remains associated with its household.

### Persistence

- Goals survive service/application reload.
- Contributions survive reload.
- Aggregate progress survives reload.

### Multi-User Goals

- Multiple applicable household members can contribute.
- Individual contributions remain attributable to the correct users.
- Overall progress reflects valid contributions from all applicable users.

---

## Implementation Plan

### PR 1: Family Goals Foundation

Implement the core goal system independently of production task lifecycle integration.

Scope:

- `Goal` model
- `GoalContribution` model
- Goal type definitions
- Goal metric definitions
- Goal period definitions
- Goal activity type definitions
- Firestore serialization/deserialization
- `GoalService`
- Goal persistence
- Contribution persistence
- Participant eligibility
- Progress calculation
- Completion detection
- Duplicate activity prevention
- Household isolation
- Required Firestore rules
- Automated model/service tests

Tests may provide simulated Famotive activity directly to `GoalService`.

Production task approval behavior should not be modified in this PR.

### PR 2: Famotive Activity Integration

Connect the goal engine to existing Famotive activity.

Initial integration:

```text
Approved Task
├── Tasks Completed
├── XP Earned
└── Coins Earned
```

Scope:

- Connect task approval to goal processing.
- Preserve existing task approval behavior.
- Preserve existing XP and Coin awarding behavior.
- Update applicable active household goals.
- Ensure one approved task cannot contribute twice to the same goal.
- Add integration/regression tests.

### PR 3: Family Goals UI

Expose the goal system to applicable users.

Scope:

- Active goal display.
- Daily/weekly goal presentation.
- Current/target progress.
- Individual contribution display.
- Shared contribution display.
- Completed goal presentation.
- Appropriate completion feedback.
- Individual, family, and team goal presentation.

UI ownership may be coordinated separately between team members.

---

## Out of Scope

The following functionality is not part of Family Challenges & Goals:

- Household leaderboards.
- Competitive rankings.
- Sibling-versus-sibling competition.
- Winner determination.
- Competitive challenge results.
- Automatic goal-completion rewards.
- Steam integration.
- Google Play or Apple reward integration.
- Mini-game integration.
- Custom goal periods unless later required.

Competitive functionality belongs to the separate Household Competition feature.

---

## Open Product Decisions

The architecture supports these decisions without requiring them to be finalized for the initial backend foundation.

### Goal Creation

The current requirements do not specify whether goals are:

- Manually created by parents.
- Automatically generated by Famotive.
- Selected from predefined Famotive goals.
- Some combination of the above.

The backend should support goal creation without assuming a specific future creation experience.

### Family Goal Eligibility

Family goals currently assume eligible household members may contribute.

The team may later decide whether family goals should:

- Include children only.
- Include parents and children.
- Allow configurable eligibility.

### Goal Completion Rewards

The current feature requires completion feedback but does not define a reward for completing a goal.

No additional XP or Coins should be awarded automatically until a separate product decision defines completion rewards and their interaction with progression.

---

## Design Boundary

Family Challenges & Goals answers:

> "What are we working toward together, and how much progress have we made?"

Household Competition answers:

> "How do household members compare against each other?"

Keeping these systems separate allows Famotive to support cooperative motivation without coupling goals to rankings or competition.