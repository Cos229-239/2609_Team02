# Rex's Room (child experience prototype)

A standalone WebGL (three.js) voxel pet game for the Famotive child view. It
does not touch the Flutter app in `lib/`.

Rex lives in his nest bed in the middle of the screen. Swipe **left** to open
**Tasks** and **right** to open the **Reward Store**. On screens 1100px wide or
more, both panels sit beside the room instead.

## Run

```bash
python3 -m http.server 8765 --directory games/rex
```

Then open `http://localhost:8765/`. The iOS Simulator reaches it at the same
address in Safari.

Query flags: `?reset=1` starts a new save, `?demo=0` turns off demo
auto-approval, and `?debug=1` shows an input-event log.

## How the care loop works (`src/game.js`)

- Four needs (food, fun, clean, energy) drop over real time. Health falls
  while Rex is neglected and recovers while he's cared for.
- With no care at all, Rex gets **sick** after about 42h and becomes a
  **fossil** after about 61h. Claiming 3 tasks digs him back up.
- Task flow: `pending` → child taps **Done!** → `completed` (waiting for a
  grown-up) → `approved` → child taps **Claim** for coins, XP and a boost to
  one need. In demo mode, tasks are approved automatically after 2.5s.
- Coins buy care items (treats, bubble bath, medicine), toys, room decor, and
  family rewards. Family rewards send a request to a parent.
- Settings has a time-speed switch (60× / 600×) and demo tools: add coins,
  make Rex sick, fossilize him, or reset the game.

## Care scenes (`src/care/`)

Feed, Play, Wash and Medicine each open a short scene: Rex bounces, the
shutter closes on him, and the scene plays in place of the room. The item
(treat, soap, medicine) is only used up when the child finishes; leaving
early (✕) costs nothing. `Game.careCheck(act)` decides whether a scene can
open (e.g. no treats → toast).

- **Kitchen** (`kitchen.js`): tap the leg bone into the pan, press and hold
  to heat it (release at "Just right!" for a perfect cook; too long and it's
  crispy), then drag it to Rex or tap him.
- **Backyard** (`yard.js`): swipe up to throw (or tap a spot on the grass);
  Rex fetches and drops the ball back. Three fetches.
- **Bath** (`bath.js`): rub over Rex for each step: hose, soap (mud turns to
  foam), hose the foam off, brush teeth (mouth open), towel dry.
- **Nurse's office** (`nurse.js`): always opens, medicine or not. Nurse Penny
  explains that Rex gets sick when tasks aren't done, checks him, then says
  he's healthy, explains how to get Dino Medicine, or asks to treat him.

`?test=1` exposes `window.__rex` (director, game, world) for automated
play-tests.

## In the Flutter app

The Home tab shows a "Visit Rex" card (`lib/features/rex/widgets/rex_room_card.dart`)
that opens `RexRoomScreen` (`lib/features/rex/rex_room_screen.dart`, route `/rex`).
That screen loads the bundled `assets/rex/index.html` into a WebView with
`window.REX_EMBED = { player: childId }` injected. This gives each child their
own save, removes the demo tools and family rewards, and adds a 🏠 button.

After any change here, rebuild the bundle:

```bash
cd games/rex && npm install && npm run build
```

The bridge:

- **App → game:** `RexGame.setTasks([...])` runs on load and whenever
  `DatabaseService` changes. Each task sends `id`, `title`, `icon` (emoji),
  `rewardXp`, `coinReward`, `status` (`pending` / `completed` / `approved`)
  and `care`. Other calls: `RexGame.approveTask(id)`, `setCoins(n)`,
  `setName(s)`, `getState()`.
- **Game → app:** messages go through the `FamotiveBridge` JavaScriptChannel.
  - `ready`: the app pushes the child's tasks.
  - `taskCompleted`: the app runs the normal `startTaskCompletion` flow,
    including photo proof, so a parent still approves the task.
  - `close`: the app pops the screen.
- When the child claims an approved task in the game, that claim stays saved
  even when the task list is refreshed, so the task isn't offered again.
- Rex's coins are an in-game balance, earned by claiming approved tasks and
  spent only on Rex items. The child's real coins and rewards stay in the app.

## Files

| File | What it does |
| --- | --- |
| `src/voxel.js` | Voxel grid → InstancedMesh builder |
| `src/rex.js` | Jointed voxel Rex and his animations, the fossil, and Ptero Pal |
| `src/room.js` | Bedroom, nest bed, pixel-art window and posters, unlockable decor |
| `src/world.js` | Renderer (low-res, pixelated upscale), camera framing, lighting |
| `src/game.js` | Save state, decay rules, tasks, store, care actions |
| `src/main.js` | HUD and panels, swipe/tap input, events, bridge |
| `src/data.js` | Demo tasks and store catalogue |
