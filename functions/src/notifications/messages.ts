import type { NotificationKind } from './plan';

/** Everything the copy for a notification might mention. */
export interface MessageContext {
  taskTitle?: string;
  rewardXp?: number;
  coinReward?: number;
  /** Who made the change (e.g. the parent who assigned a task). */
  actorName?: string;
  /** The child the notification is about (parent-facing notifications). */
  childName?: string;
  rewardTitle?: string;
  rewardIcon?: string;
  coinCost?: number;
  /** Morning digest contents (titles of each group). */
  digest?: { due: string[]; overdue: string[]; pool: string[] };
}

export interface MessageContent {
  title: string;
  body: string;
}

const quoted = (s: string | undefined, fallback: string) => (s && s.trim() ? `"${s.trim()}"` : fallback);

function rewardSuffix(ctx: MessageContext): string {
  const parts: string[] = [];
  if (ctx.rewardXp) parts.push(`+${ctx.rewardXp} XP`);
  if (ctx.coinReward) parts.push(`+${ctx.coinReward} coins`);
  return parts.length ? ` (${parts.join(', ')})` : '';
}

const countOf = (n: number) => `${n} quest${n === 1 ? '' : 's'}`;

/** "A, B and 2 more" from task titles (blank titles skipped). */
function listTitles(titles: string[], max = 2): string {
  const t = titles.map((x) => x.trim()).filter(Boolean);
  if (t.length === 0) return 'check your list';
  if (t.length <= max) return t.join(' and ');
  return `${t.slice(0, max).join(', ')} and ${t.length - max} more`;
}

/** Kid-friendly (child) / at-a-glance (parent) notification copy. */
export function buildMessage(kind: NotificationKind, ctx: MessageContext): MessageContent {
  const task = quoted(ctx.taskTitle, 'a quest');
  const child = ctx.childName?.trim() || 'Your child';

  switch (kind) {
    case 'task_available':
      return {
        title: 'New quest available! 🗺️',
        body: `${task} is up for grabs — claim it first${rewardSuffix(ctx)}.`,
      };
    case 'task_assigned':
      return {
        title: 'New quest assigned ⚔️',
        body: ctx.actorName?.trim()
          ? `${ctx.actorName.trim()} gave you ${task}${rewardSuffix(ctx)}.`
          : `You've been given ${task}${rewardSuffix(ctx)}.`,
      };
    case 'task_due':
      return {
        title: 'Quest due today ⏰',
        body: `Don't forget ${task}${rewardSuffix(ctx)}!`,
      };
    case 'task_overdue':
      return {
        title: 'Quest overdue ⌛',
        body: `${task} is past due — finish it to still earn your rewards.`,
      };
    case 'daily_digest': {
      const d = ctx.digest ?? { due: [], overdue: [], pool: [] };
      const parts: string[] = [];
      if (d.due.length) parts.push(`${countOf(d.due.length)} due today: ${listTitles(d.due)}`);
      if (d.overdue.length) parts.push(`${d.overdue.length} overdue from yesterday`);
      if (d.pool.length) parts.push(`${d.pool.length} up for grabs`);
      return {
        title: "Today's quests 🗺️",
        body: parts.length ? `${parts.join(' · ')}.` : 'Check your quests for today.',
      };
    }
    case 'task_approved': {
      const earned: string[] = [];
      if (ctx.rewardXp) earned.push(`+${ctx.rewardXp} XP`);
      if (ctx.coinReward) earned.push(`+${ctx.coinReward} coins`);
      return {
        title: 'Quest approved! 🎉',
        body: earned.length
          ? `${task} was approved — you earned ${earned.join(' and ')}!`
          : `${task} was approved — great job!`,
      };
    }
    case 'task_accepted':
      return {
        title: `${child} accepted a task`,
        body: `${task} was claimed from the task pool.`,
      };
    case 'task_completed':
      return {
        title: `${child} completed a task ✅`,
        body: `${task} is ready for your approval.`,
      };
    case 'reward_redeemed': {
      const reward = `${ctx.rewardIcon ? `${ctx.rewardIcon} ` : ''}${ctx.rewardTitle?.trim() || 'a reward'}`;
      const cost = ctx.coinCost ? ` for ${ctx.coinCost} coins` : '';
      return {
        title: `${child} redeemed a reward 🎁`,
        body: `${reward}${cost}.`,
      };
    }
  }
}
