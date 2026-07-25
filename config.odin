package main

import rl "vendor:raylib"

// Tunable constants ported 1:1 from the original glox game's config.lox /
// levels.lox. Values are frame counts at a locked 60fps, not seconds -- see
// the porting plan for why this is deliberate (matches the original's tuned
// feel exactly).

WIDTH :: 1300
HEIGHT :: 1000
FULLSCREEN :: true

WORLD_SCALE :: 10
WORLD_WIDTH :: WIDTH * WORLD_SCALE // 13000

TARGET_FPS :: 60

LANDER_WAVES :: 3
LANDER_WAVE_DELAY :: 600
LANDER_SEARCH_SPEED :: 2.5
LANDER_ASCEND_SPEED :: 2.5
MUTANT_SPEED_PCT :: 0.7

// Not part of the original glox port (its pick_a_human just took the first
// unclaimed human in list order) -- added at the user's request so landers
// target the nearest unclaimed human instead, within a radius that shrinks
// each wave. See human_search_radius() in entity.odin.
SEARCH_RADIUS_BASE :: 3000
SEARCH_RADIUS_STEP :: 400 // shrink per wave
SEARCH_RADIUS_MIN :: 600 // floor, roughly half a screen width

SWARMERS_PER_POD :: 10

BAITER_THRESHOLD :: 3
BAITER_DELAY :: 600

HUMANS :: 20
HUMAN_DROP_ACCEL :: 0.05
HUMANS_EVERY_N_LEVELS :: 3

STARTING_LIVES :: 3
STARTING_BOMBS :: 5

PLAYER_MAXSPEED :: 28
PLAYER_ACCEL :: 0.7
PLAYER_FRICTION :: 0.96
PLAYER_VSPEED :: 7
PLAYER_LEAN_SPEED :: 1.5
LEFTOFFSET :: f32(WIDTH) * 0.15
RIGHTOFFSET :: f32(WIDTH) - f32(WIDTH) * 0.15
OFFSETSPEED :: 10

NODIE :: false // if true, the player ship cannot die (for testing)

HYPERSPACE_DEATH_CHANCE :: 8 // 1-in-8
HYPERSPACE_DISPERSE_START :: 50
HYPERSPACE_MATERIALISE_RATE :: 0.7
HYPERSPACE_MIN_NPC_DIST :: 400
HYPERSPACE_MAX_ATTEMPTS :: 20

SAFE_START_FRAMES :: 60
THRUST_SCALE :: 0.75
THRUST_GAP :: 6

NPC_BULLET_TIME_BASE :: 180 // level-1 baseline; overridden by Level.npc_bullet_time

EXPLOSION_PARTICLES :: 140
BONUS_LIFE :: 90

PLAYER_TOP :: f32(HEIGHT) * 0.16
PLAYER_BOTTOM :: f32(HEIGHT) - 50

BOMB_PASS_DELAY :: 5
BOMB_FLASH_FRAMES :: 8

LEVEL_FINISH_DISPLAY_TIME :: 240 // post-tally hold before the next level starts
GAME_OVER_PAUSE :: 180

// End-of-wave human bonus tally: not part of the original glox port (its
// level_finish just showed the banner) -- added per the user's request to
// match the arcade original's count-up. Bonus per surviving human is
// 100 x wave number, capped at wave 5 (500/human).
TALLY_BONUS_PER_LEVEL :: 100
TALLY_BONUS_MAX_LEVEL :: 5
TALLY_TICK_FRAMES :: 4 // frames between each human reveal (~0.07s)
TALLY_ICON_SCALE :: 2.0
TALLY_COLS :: 20 // humans per row before wrapping
TALLY_COL_GAP :: 40
TALLY_ROW_GAP :: 40
TALLY_TOP_Y :: f32(HEIGHT) * 0.55
BANNER_Y :: f32(HEIGHT) * 0.22 // "ATTACK WAVE N COMPLETED." sits in the upper screen, tally below it

// Intro screen: not part of the original glox port (its intro was plain
// text) -- sequence and timings adapted from love2d-defender-master's
// game/intro.lua (Williams logo flash -> "presents" colour-cycles in ->
// DEFENDER title shatters into place with a colour-cycling highlight ->
// control instructions), converted from that project's dt-seconds timers
// to frame counts at our locked 60fps.
INTRO_WILLIAMS_FLASH_FRAMES :: 12 // 0.2s per colour, matches the original
INTRO_PRESENTS_AT :: 120 // 2s
INTRO_TITLE_AT :: 240 // 4s
INTRO_TEXT_AT :: 360 // 6s
INTRO_DISPERSE_START :: 30
INTRO_DISPERSE_RATE :: 0.25 // ~2s (120 frames) to fully converge, matching the original
INTRO_PRESENTS_CYCLE_STEPS :: 30 // 0.5s period, matches the original
INTRO_HILITE_CYCLE_STEPS :: 6 // 0.1s period, matches the original
INTRO_WILLIAMS_Y :: f32(100)
INTRO_PRESENTS_Y :: f32(220)
INTRO_TITLE_Y :: f32(400)
INTRO_TEXT_Y :: f32(HEIGHT) - 100 // matches the original's "screen height - 100"
// presents.png ships as a huge mostly-transparent canvas (935x768) with the
// actual "PRESENTS" art in a small region -- cropped to that region so it
// draws at a sane size instead of overlaying most of the screen.
INTRO_PRESENTS_SRC :: rl.Rectangle{304, 259, 665 - 304, 665 - 259}

LIVES_ICON_SCALE :: 0.45
LIVES_ICON_GAP :: 34
LIVES_ICON_MAX :: 7
LIVES_ROW_X :: 10
LIVES_ROW_Y :: 50

BOMB_ICON_SCALE :: 0.5
BOMB_ICON_GAP :: 20
BOMB_ICON_MAX :: 7
BOMB_COLUMN_GAP :: 8

FONT_PITCH :: 30
FONT_INK_W :: 20
FONT_INK_H :: 30
FONT_ADVANCE :: 25
FONT_CHARS :: "0123456789:?ABCDEFGHIJKLMNOPQRSTUVWXYZ" // 38 glyphs

LASER_NUM_GAPS :: 10

MOUNTAIN_EXPLODE_POINTS_PER_FRAME :: 2000
MOUNTAIN_JITTER_MAX :: 25
MOUNTAIN_COLLAPSE_CHANCE :: 40 // 1-in-40
MOUNTAIN_COLLAPSE_HEIGHT :: 100000

// Pool capacities. Sized from the Level-6 worst case (see the porting plan) --
// everything lives in fixed arrays; nothing grows during play.
MAX_ENTITIES :: 128
MAX_PENDING_SPAWNS :: 96
MAX_BULLETS :: 100
MAX_LASERS :: 12
MAX_PARTICLES :: 16384
MAX_BONUSES :: 16
MAX_EVENTS_PER_FRAME :: 256

Level :: struct {
	landers_per_wave: int,
	pods:              int,
	bombers:           int,
	npc_bullet_time:   int,
	max_baiters:       int,
}

LEVELS := [6]Level{
	{5, 0, 0, 180, 1},
	{6, 0, 2, 180, 1},
	{7, 1, 3, 120, 1},
	{8, 2, 4, 120, 1},
	{9, 2, 5, 120, 2},
	{10, 3, 5, 120, 3},
}

// apply_level copies level n's (1-based, clamped past the last entry)
// npc_bullet_time/max_baiters into the entity manager's scalar state.
// landers_per_wave/pods/bombers aren't stored anywhere -- game_controller's
// enter_level_start reads them directly from LEVELS since nothing else
// needs them. Ported from levels.lox's apply_level().
apply_level :: proc(g: ^Game, n: int) {
	idx := clamp_int(n-1, 0, len(LEVELS)-1)
	lvl := LEVELS[idx]
	g.mgr.npc_bullet_time = lvl.npc_bullet_time
	g.mgr.max_baiters = lvl.max_baiters
}
