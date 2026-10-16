// Demo content. Task fields mirror lib/core/models/task.dart (title, icon,
// rewardXp, coinReward, status) and store prices mirror Reward.coinCost.
// `status` here: pending → completed (waiting on parent) → approved → claimed.

export const DEMO_TASKS = [
  { id: 't1', title: 'Make Bed', icon: '🛏️', rewardXp: 10, coinReward: 10, care: 'energy', status: 'approved' },
  { id: 't2', title: 'Sweep Kitchen', icon: '🧹', rewardXp: 15, coinReward: 15, care: 'clean', status: 'approved' },
  { id: 't3', title: 'Put Away Laundry', icon: '🧺', rewardXp: 15, coinReward: 15, care: 'clean', status: 'pending' },
  { id: 't4', title: 'Help Set the Table', icon: '🍽️', rewardXp: 10, coinReward: 10, care: 'hunger', status: 'pending' },
  { id: 't5', title: 'Clean Room', icon: '🧸', rewardXp: 20, coinReward: 20, care: 'clean', status: 'pending' },
  { id: 't6', title: 'Read for 20 Minutes', icon: '📚', rewardXp: 15, coinReward: 10, care: 'fun', status: 'pending' },
  { id: 't7', title: 'Take Out Trash', icon: '🗑️', rewardXp: 10, coinReward: 10, care: 'clean', status: 'completed' },
  { id: 't8', title: 'Brush Teeth', icon: '🪥', rewardXp: 5, coinReward: 5, care: 'clean', status: 'claimed' },
];

export const CARE = {
  hunger: { icon: '🍖', label: 'Food' },
  fun: { icon: '⚽', label: 'Fun' },
  clean: { icon: '🫧', label: 'Clean' },
  energy: { icon: '⚡', label: 'Energy' },
};

// kind: consumable (stacks in inventory), toy/decor/cosmetic/pet (owned once),
// family (a real-world reward request sent to a parent).
export const STORE_ITEMS = [
  { id: 'treat', name: 'Dino Treats', icon: '🍗', cost: 25, kind: 'consumable', cat: 'care', tint: '#ffe3cf', desc: 'Feeds Rex (+35 food)' },
  { id: 'soap', name: 'Bubble Bath', icon: '🧼', cost: 30, kind: 'consumable', cat: 'care', tint: '#dff2ff', desc: 'Cleans Rex (+40 clean)' },
  { id: 'medicine', name: 'Dino Medicine', icon: '💊', cost: 60, kind: 'consumable', cat: 'care', tint: '#ffe0ea', desc: 'Makes a sick Rex better' },
  { id: 'ball', name: 'Ball', icon: '⚽', cost: 75, kind: 'toy', cat: 'toys', tint: '#dbe8ff', desc: 'Unlocks Play' },
  { id: 'hat', name: 'New Hat', icon: '🧢', cost: 100, kind: 'cosmetic', cat: 'toys', tint: '#ffe0e0', desc: 'A cool red cap' },
  { id: 'plush', name: 'T-Rex Plush', icon: '🦖', cost: 150, kind: 'decor', cat: 'decor', tint: '#e2f6dc', desc: 'Sits on the shelf' },
  { id: 'plant', name: 'Room Plant', icon: '🪴', cost: 200, kind: 'decor', cat: 'decor', tint: '#e5f3e0', desc: 'A big leafy plant' },
  { id: 'glowEgg', name: 'Glow Egg', icon: '🥚', cost: 250, kind: 'decor', cat: 'decor', tint: '#dcfaf0', desc: 'Glows in the dark' },
  { id: 'background', name: 'Sunset View', icon: '🌄', cost: 400, kind: 'decor', cat: 'decor', tint: '#ffe9d6', desc: 'New window view' },
  { id: 'ptero', name: 'Ptero Pal', icon: '🦅', cost: 600, kind: 'pet', cat: 'toys', tint: '#ece3ff', desc: 'A flying friend' },
  { id: 'screen30', name: '30 min Screen Time', icon: '📱', cost: 200, kind: 'family', cat: 'family', tint: '#fff4cc', desc: 'Ask a parent' },
  { id: 'dinner', name: 'Pick Dinner', icon: '🍕', cost: 300, kind: 'family', cat: 'family', tint: '#fff4cc', desc: 'Ask a parent' },
];

export const STORE_TABS = [
  { id: 'all', label: 'All' },
  { id: 'care', label: 'Care' },
  { id: 'toys', label: 'Toys' },
  { id: 'decor', label: 'Decor' },
  { id: 'family', label: 'Family' },
];
