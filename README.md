# Defender

A Defender-style side-scrolling arcade shooter, written in [Odin](https://odin-lang.org/)
using [raylib](https://www.raylib.com/) for rendering, input, and audio-ready plumbing.

Rescue colonists from landers before they're carried off and mutate, fend off pods,
swarmers, baiters, and bombers, and clear each attack wave to advance.

## Building and running

Requires the Odin compiler (see [odin-lang.org](https://odin-lang.org/) for installation).
`vendor:raylib`, used throughout, ships with the compiler.

From this directory:

```
odin run . -out:defender.exe
```

or to build without running:

```
odin build . -out:defender.exe
```

The recommended check flags (also worth running before committing changes):

```
odin check . -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors
```

## Controls

| Key | Action |
|---|---|
| Right Shift | Thrust (hold) |
| Space | Reverse facing (tap) |
| Q / A | Move up / down |
| Enter | Fire laser |
| Backspace | Smart bomb |
| Left Shift | Hyperspace *(not yet implemented)* |
| Escape | Quit |

## Architecture

Everything lives in fixed-capacity pools, allocated once at startup — entities, bullets,
lasers, particles, bonus popups, and the spawn queue are all plain arrays with an
`active`/occupancy flag, scanned for a free slot rather than grown dynamically. Nothing
allocates on the heap once the game is running (the one exception is `context.temp_allocator`
for transient HUD text formatting, reset every frame).

Every stateful object (player, each NPC kind, the game's own level/menu flow) follows the
same convention: a per-instance `update_func`/`draw_func` procedure pointer, changed only
via a matching `enter_<state>` procedure that performs one-off setup before installing the
new state. This keeps each state machine's transitions in one obvious place per state,
rather than scattered condition checks.

Game-wide happenings (kills, rescues, spawns, level transitions) go through a fixed-size
per-frame event queue (`event.odin`) rather than direct calls between systems, so e.g. the
score counter, the bonus-popup display, and the level controller can each react to the same
event without knowing about each other.

### Source layout

All game code lives in one Odin package (`package main`), split across files by subsystem
rather than by package, since the game's systems are tightly coupled (nearly everything
ultimately reaches back into the top-level `Game` struct) and Odin packages must form an
acyclic import graph.

| File | Contents |
|---|---|
| `main.odin` | Entry point: window setup, main loop |
| `game.odin` | Top-level `Game` struct, per-frame update/draw orchestration |
| `config.odin` | Tunable constants and the per-level difficulty table |
| `entity.odin` | Shared `Entity` struct/pool used by every enemy and human |
| `entity_mgr.odin` | Collisions, smart bomb, wave-clear, baiter spawning |
| `npc_*.odin` | Per-kind behaviour: lander/mutant, pod, swarmer, baiter, bomber, human |
| `player.odin`, `controller.odin` | Ship state machine and input polling |
| `bullet.odin`, `laser.odin`, `particle.odin`, `bonus.odin` | Pooled projectiles/effects/popups |
| `spawn_queue.odin` | Delayed entity spawning |
| `game_controller.odin` | Intro/level/game-over state machine, HUD icons, intro animation |
| `score.odin`, `text.odin`, `radar.odin` | HUD score, bitmap font, minimap |
| `camera.odin`, `mountains.odin`, `stars.odin`, `collide.odin` | World scrolling, terrain, starfield, collision math |
| `sprite_sheet.odin` | Sprite-sheet animation and the shatter/disperse effect |
| `event.odin` | The per-frame event queue |
| `assets.odin`, `colors.odin`, `util.odin` | Texture loading, named colours, small helpers |

## Known gaps

- Hyperspace (warping to a random on-screen location) is not yet implemented.
- TODO: sound. No audio is wired up yet (sound effects for firing, explosions,
  rescues, etc.).
