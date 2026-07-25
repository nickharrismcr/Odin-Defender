package main

import "core:fmt"
import rl "vendor:raylib"

// Drives the level/game-state machine: intro -> level_start -> level ->
// level_finish -> level_start (loops), or -> game_over. Mirrors the
// enter_<state>/state_<state> convention used elsewhere. Ported from
// game/game_controller.lox.
//
// level_finish is the wave-complete screen: entering it clears every enemy/
// bullet/laser (humans persist) and hides the ship, and pushes a
// Level_Finish event that Mountains reacts to by hiding itself (see
// apply_mountain_events in mountains.odin); draw_frame additionally hides
// the starfield/entities/radar for the whole state, so nothing but the
// banner and human tally show. Not part of the original glox port (its
// level_finish just showed the "ATTACK WAVE N COMPLETED." banner) -- the
// human bonus count-up below is ported from the arcade original's actual
// end-of-wave behaviour instead. The banner ("ATTACK WAVE N COMPLETED.",
// upper screen) shows throughout; surviving humans tally up one at a time
// underneath it (lower screen), each awarding 100 x wave number points
// (capped at wave 5, so 500/human). Once every human is counted, the
// screen holds for LEVEL_FINISH_DISPLAY_TIME more before handing off to
// level_start, which spawns the next level's entities, reveals the ship,
// and pushes Level_Start (undoing the hides).
Controller_State :: enum {
	Intro,
	Level_Start,
	Level,
	Level_Finish,
	Game_Over,
}

Game_Controller :: struct {
	state:          Controller_State,
	level:          int,
	lives:          int,
	landers_killed: int,
	level_landers:  int,
	timer:          int,
	banner_level:   int, // level number for the "ATTACK WAVE N COMPLETED." banner, formatted fresh each draw
	done:           bool,

	// end-of-wave human bonus tally (see the file-level doc comment)
	tally_count:    int, // humans surviving at level_finish entry
	tally_revealed: int, // how many have been counted/awarded so far
	tally_timer:    int, // frames until the next reveal

	update_func: proc(^Game, ^Input),

	// own textures, each locked to a single static frame (start_frame ==
	// end_frame): every draw call advances a sheet's animation as a side
	// effect, so reusing the real ship/smartbomb sheets here would make
	// them animate LIVES_ICON_MAX/BOMB_ICON_MAX times too fast.
	lives_icon: Sprite_Sheet,
	bomb_icon:  Sprite_Sheet,

	// same palette/speed as the score (see score.odin), for a consistent HUD look
	banner_cycle: Colour_Cycle,

	// intro screen animation (see the Intro case in draw_game_controller
	// and state_intro) -- not part of the original glox port, see config.odin
	intro_timer:     int, // frames since the intro began
	title_disperse:  f32, // shatter-in amount for the DEFENDER title, converges to 1
	presents_cycle:  Colour_Cycle,
	hilite_cycle:    Colour_Cycle,
	title_sheet:     Sprite_Sheet, // 1-frame wrap so the title can reuse sprite_draw_disperse
	title_hilite_sheet: Sprite_Sheet,
}

init_game_controller :: proc(a: ^Assets) -> Game_Controller {
	gc: Game_Controller
	gc.lives = STARTING_LIVES
	gc.state = .Intro
	gc.update_func = state_intro
	gc.lives_icon = make_sprite_sheet(a.ship, 5, 1, 1)
	gc.bomb_icon = make_sprite_sheet(a.smartbomb, 1, 1, 1)
	gc.banner_cycle = make_colour_cycle(SCORE_PALETTE, 45)

	gc.title_disperse = INTRO_DISPERSE_START
	gc.presents_cycle = make_colour_cycle(SCORE_PALETTE, INTRO_PRESENTS_CYCLE_STEPS)
	gc.hilite_cycle = make_colour_cycle(SCORE_PALETTE, INTRO_HILITE_CYCLE_STEPS)
	gc.title_sheet = make_sprite_sheet(a.title, 1, 1, 1)
	gc.title_hilite_sheet = make_sprite_sheet(a.title_hilite, 1, 1, 1)
	return gc
}

// Gameplay (ship/entities update, collisions) runs during level_start and
// level; it's frozen during intro, the level_finish pause, and game_over.
gameplay_active :: proc(g: ^Game) -> bool {
	return g.controller.state == .Level_Start || g.controller.state == .Level
}

// Scans this frame's event queue for the four kinds the original subscribes
// to via entities.events.on(...) in GameController's constructor.
apply_controller_events :: proc(g: ^Game) {
	for i in 0 ..< g.events.count {
		#partial switch g.events.events[i].kind {
		case .Lander_Killed, .Mutant_Killed:
			g.controller.landers_killed += 1
		case .Player_Die:
			g.controller.lives -= 1
		case .Player_Start:
			if g.controller.lives < 0 {
				enter_game_over(g)
			}
		}
	}
}

// Runs the state-machine tick (dispatch to update_func) and the banner
// colour cycle. Called from game.odin AFTER apply_controller_events (and
// every other consumer) has already applied this frame's events -- so
// state_level's landers-killed check reacts the instant the count is
// updated, same frame, not on a later poll.
tick_game_controller :: proc(g: ^Game, in_: ^Input) {
	colour_cycle_update(&g.controller.banner_cycle)
	g.controller.update_func(g, in_)
}

// --- states ----------------------------------------------------------------

state_intro :: proc(g: ^Game, in_: ^Input) {
	gc := &g.controller
	gc.intro_timer += 1
	colour_cycle_update(&gc.presents_cycle)
	colour_cycle_update(&gc.hilite_cycle)
	if gc.intro_timer > INTRO_TITLE_AT {
		gc.title_disperse = max(gc.title_disperse-INTRO_DISPERSE_RATE, 1)
	}
	if in_.reverse { // SPACE, same key as the arcade "press space to start" -- skips the animation
		enter_level_start(g)
	}
}

enter_level_start :: proc(g: ^Game) {
	g.controller.level += 1
	apply_level(g, g.controller.level)
	lvl := LEVELS[clamp_int(g.controller.level-1, 0, len(LEVELS)-1)]

	g.controller.landers_killed = 0
	g.controller.level_landers = lvl.landers_per_wave * LANDER_WAVES

	for i in 0 ..< LANDER_WAVES {
		add_landers(g, lvl.landers_per_wave, i*LANDER_WAVE_DELAY)
	}
	// guarantee one lander materialises in view (roughly screen-centre)
	add_lander_near(g, g.player.pos.x+f32(WIDTH)*0.35, 0)
	add_pods(g, lvl.pods, g.player.pos.x)
	add_bombers(g, lvl.bombers)
	if (g.controller.level-1) % HUMANS_EVERY_N_LEVELS == 0 {
		add_humans(g, HUMANS)
	}

	// Only force the ship visible if it's just coasting along in normal
	// play -- if it's mid death-sequence/hyperspace/spawn-wait, that
	// state's own enter_/state_ functions already own visibility (e.g. a
	// level ending mid-explode shouldn't reveal the ship early).
	if g.player.update_func == state_play {
		g.player.visible = true
	}
	g.controller.state = .Level_Start
	g.controller.update_func = state_level_start
	push_event(&g.events, {kind = .Level_Start, level = g.controller.level})
}

state_level_start :: proc(g: ^Game, in_: ^Input) {
	enter_level(g)
}

enter_level :: proc(g: ^Game) {
	g.controller.state = .Level
	g.controller.update_func = state_level
}

state_level :: proc(g: ^Game, in_: ^Input) {
	if g.controller.lives >= 0 && g.controller.landers_killed >= g.controller.level_landers {
		enter_level_finish(g)
	}
}

enter_level_finish :: proc(g: ^Game) {
	// count before clear_wave, though clear_wave leaves humans alone anyway
	g.controller.tally_count = count_active_humans(g)
	g.controller.tally_revealed = 0
	g.controller.tally_timer = TALLY_TICK_FRAMES

	clear_wave(g)
	g.player.visible = false
	g.controller.banner_level = g.controller.level
	g.controller.timer = LEVEL_FINISH_DISPLAY_TIME
	g.controller.state = .Level_Finish
	g.controller.update_func = state_level_finish
	push_event(&g.events, {kind = .Level_Finish, level = g.controller.level})
}

count_active_humans :: proc(g: ^Game) -> int {
	n := 0
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if e.active && e.kind == .Human {
			n += 1
		}
	}
	return n
}

// Reveals one surviving human at a time, awarding its bonus directly to
// the score (bypassing the event queue -- the bonus amount depends on the
// current wave number, which only game_controller readily knows, so
// there's no shared Event_Kind for it). Once every human is tallied (or
// there were none), holds for LEVEL_FINISH_DISPLAY_TIME before the next
// level starts.
state_level_finish :: proc(g: ^Game, in_: ^Input) {
	if g.controller.tally_revealed < g.controller.tally_count {
		g.controller.tally_timer -= 1
		if g.controller.tally_timer <= 0 {
			g.controller.tally_revealed += 1
			g.score.value += min(g.controller.level, TALLY_BONUS_MAX_LEVEL) * TALLY_BONUS_PER_LEVEL
			g.controller.tally_timer = TALLY_TICK_FRAMES
		}
		return
	}
	if g.controller.timer > 0 {
		g.controller.timer -= 1
		return
	}
	enter_level_start(g)
}

enter_game_over :: proc(g: ^Game) {
	g.controller.timer = GAME_OVER_PAUSE
	g.controller.state = .Game_Over
	g.controller.update_func = state_game_over
}

state_game_over :: proc(g: ^Game, in_: ^Input) {
	if g.controller.timer > 0 {
		g.controller.timer -= 1
		if g.controller.timer <= 0 {
			g.controller.done = true
		}
	}
}

// --- draw ------------------------------------------------------------------

draw_game_controller :: proc(g: ^Game) {
	switch g.controller.state {
	case .Intro:
		draw_intro(g)
	case .Level_Finish:
		banner := fmt.tprintf("ATTACK WAVE %d COMPLETED.", g.controller.banner_level)
		draw_centered(&g.font, banner, f32(WIDTH)/2, BANNER_Y, colour_cycle_get(&g.controller.banner_cycle))
		if g.controller.tally_count > 0 {
			bonus := min(g.controller.banner_level, TALLY_BONUS_MAX_LEVEL) * TALLY_BONUS_PER_LEVEL
			bonus_text := fmt.tprintf("BONUS X %d", bonus)
			draw_centered(&g.font, bonus_text, f32(WIDTH)/2, TALLY_TOP_Y-40, colour_cycle_get(&g.controller.banner_cycle))
		}
		draw_human_tally(g)
	case .Game_Over:
		draw_centered(&g.font, "GAME OVER", f32(WIDTH)/2, f32(HEIGHT)/2, COLOUR_RED)
	case .Level_Start, .Level:
	}
	if g.controller.state != .Intro {
		draw_lives(g)
		draw_bombs(g)
	}
}

draw_centered :: proc(font: ^Font, s: string, cx, y: f32, col: rl.Color) {
	font_draw(font, s, cx-font_width(s)/2, y, col)
}

// Intro screen sequence: not part of the original glox port -- adapted
// from love2d-defender-master's game/intro.lua (see config.odin for the
// timing/layout constants and the reasoning behind each). Williams logo
// flashes red/yellow from the start; "presents" colour-cycles in at
// INTRO_PRESENTS_AT; the DEFENDER title (plus a colour-cycling highlight
// overlay) shatters into place at INTRO_TITLE_AT, reusing the same
// disperse-draw effect used for NPC materialise/death; instructions appear
// at INTRO_TEXT_AT. SPACE skips straight to level_start at any point (see
// state_intro).
draw_intro :: proc(g: ^Game) {
	gc := &g.controller

	flash_on := (gc.intro_timer / INTRO_WILLIAMS_FLASH_FRAMES) % 2 == 0
	will_tint := COLOUR_RED if flash_on else COLOUR_YELLOW
	will_x := f32(WIDTH)/2 - f32(g.assets.williams.width)/2
	rl.DrawTextureEx(g.assets.williams, {will_x, INTRO_WILLIAMS_Y}, 0, 1, will_tint)

	if gc.intro_timer > INTRO_PRESENTS_AT {
		pres_x := f32(WIDTH)/2 - INTRO_PRESENTS_SRC.width/2
		rl.DrawTextureRec(g.assets.presents, INTRO_PRESENTS_SRC, {pres_x, INTRO_PRESENTS_Y}, colour_cycle_get(&gc.presents_cycle))
	}

	if gc.intro_timer > INTRO_TITLE_AT {
		title_x := f32(WIDTH)/2 - gc.title_sheet.frame_width/2
		sprite_draw_disperse(&gc.title_sheet, title_x, INTRO_TITLE_Y, gc.title_disperse, COLOUR_WHITE)
		sprite_draw_disperse(&gc.title_hilite_sheet, title_x, INTRO_TITLE_Y, gc.title_disperse, colour_cycle_get(&gc.hilite_cycle))
	}

	if gc.intro_timer > INTRO_TEXT_AT {
		draw_centered(&g.font, "Q=UP A=DOWN SPACE=REVERSE SHIFT=THRUST ENTER=FIRE BACKSPACE=BOMB - PRESS SPACE TO PLAY", f32(WIDTH)/2, INTRO_TEXT_Y, COLOUR_BLUE)
	}
}

// Grid of human icons, one per revealed survivor so far, wrapping at
// TALLY_COLS per row and centered horizontally. Static icons (not drawn
// through a Sprite_Sheet -- there's nothing to animate here).
draw_human_tally :: proc(g: ^Game) {
	for i in 0 ..< g.controller.tally_revealed {
		row := i / TALLY_COLS
		col := i % TALLY_COLS

		row_start := row * TALLY_COLS
		items_in_row := TALLY_COLS
		if remaining := g.controller.tally_revealed - row_start; remaining < TALLY_COLS {
			items_in_row = remaining
		}

		row_width := f32(items_in_row) * TALLY_COL_GAP
		start_x := f32(WIDTH)/2 - row_width/2
		x := start_x + f32(col)*TALLY_COL_GAP
		y := TALLY_TOP_Y + f32(row)*TALLY_ROW_GAP
		rl.DrawTextureEx(g.assets.human, {x, y}, 0, TALLY_ICON_SCALE, COLOUR_WHITE)
	}
}

// A row of small ship icons, one per life (capped at LIVES_ICON_MAX), under the score.
draw_lives :: proc(g: ^Game) {
	n := g.controller.lives
	if n > LIVES_ICON_MAX {
		n = LIVES_ICON_MAX
	}
	x := f32(LIVES_ROW_X)
	for _ in 0 ..< n {
		sprite_draw_scaled(&g.controller.lives_icon, x, LIVES_ROW_Y, COLOUR_WHITE, false, LIVES_ICON_SCALE)
		x += LIVES_ICON_GAP
	}
}

// A column of small bomb icons, one per remaining smart bomb (capped at
// BOMB_ICON_MAX), sitting flush against the radar's left edge.
draw_bombs :: proc(g: ^Game) {
	n := g.mgr.bombs
	if n > BOMB_ICON_MAX {
		n = BOMB_ICON_MAX
	}
	icon_width := g.controller.bomb_icon.frame_width * BOMB_ICON_SCALE
	x := f32(RADAR_POS) - icon_width - BOMB_COLUMN_GAP
	y := f32(0)
	for _ in 0 ..< n {
		sprite_draw_scaled(&g.controller.bomb_icon, x, y, COLOUR_WHITE, false, BOMB_ICON_SCALE)
		y += BOMB_ICON_GAP
	}
}
