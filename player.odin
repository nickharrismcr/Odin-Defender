package main

import rl "vendor:raylib"

// The player ship. Classic Defender controls: hold thrust to accelerate in
// the facing direction, tap reverse to flip facing and zero speed, Q/A to
// move up/down, Enter to fire, Backspace for smart bomb, L-Shift to
// hyperspace.
//
// A small state machine of swappable update functions. States:
//   safe_start : ship visible and already flyable, enemies hidden AND
//                frozen. Entered on construction and after every respawn.
//   play       : normal gameplay. Enemies visible and active.
//   die        : just hit -- frozen in place, flashing red. Enemies stay
//                visible but freeze too. Then -> explode.
//   explode    : ship gone, particle burst plays. Enemies hidden AND
//                frozen. Then -> safe_start.
//   hyperspace : not yet implemented (needs far_from_npcs()).
Player :: struct {
	pos:          rl.Vector2,
	sheet:        Sprite_Sheet, // ship.png, 5-frame animation
	thrust_sheet: Sprite_Sheet, // thrust.png, 2-frame flame
	flash_sheet:  Sprite_Sheet, // shipw.png, all-white silhouette tinted for the death flash

	// persistent facing (dir, +1/-1) plus a scalar speed: thrust accelerates
	// in the facing direction, reverse flips facing and zeroes speed. vx is
	// the derived signed velocity (parallax / laser inheritance).
	dir:                               f32,
	speed:                             f32,
	vx, vy:                            f32,
	maxspeed, accel, friction, vspeed: f32,

	// purely visual: while thrusting, the drawn ship eases forward (in the
	// facing direction) up to one ship-width, then eases back once released.
	// World position/physics are untouched.
	lean:       f32,
	lean_speed: f32,

	// camera look-ahead: ship sits at screen x == offset, which lerps
	// between leftoffset (facing right) and rightoffset (facing left).
	leftoffset, rightoffset: f32,
	offset:                  f32,

	world_width: f32,
	top, bottom: f32, // vertical play-area clamp

	thrusting: bool,
	visible:   bool,
	invuln:    int, // frames of blink-protected grace after a respawn

	update_func: proc(^Player, ^Game, ^Input),

	timer: int,
	flash: bool, // draw the red ship this frame (death flash)
}

init_player :: proc(a: ^Assets, pos: rl.Vector2) -> Player {
	p: Player
	p.pos = pos
	p.sheet = make_sprite_sheet(a.ship, 5, 1, 5)
	sprite_set_animate(&p.sheet, 8)
	p.thrust_sheet = make_sprite_sheet(a.thrust, 2, 1, 2)
	sprite_set_animate(&p.thrust_sheet, 6)
	p.flash_sheet = make_sprite_sheet(a.shipw, 2, 1, 2)

	p.dir = 1
	p.speed = 0
	p.maxspeed = PLAYER_MAXSPEED
	p.accel = PLAYER_ACCEL
	p.friction = PLAYER_FRICTION
	p.vspeed = PLAYER_VSPEED

	p.lean_speed = PLAYER_LEAN_SPEED

	p.leftoffset = LEFTOFFSET
	p.rightoffset = RIGHTOFFSET
	p.offset = p.leftoffset

	p.world_width = WORLD_WIDTH
	p.top = PLAYER_TOP
	p.bottom = PLAYER_BOTTOM
	p.visible = true

	// Set directly rather than via enter_safe_start, to avoid emitting a
	// Player_Start event before the game is fully constructed.
	p.update_func = state_safe_start
	p.timer = SAFE_START_FRAMES

	return p
}

player_handle_input :: proc(p: ^Player, in_: ^Input) {
	p.thrusting = false

	if in_.reverse {
		p.dir = -p.dir
		p.speed = 0
	}

	if in_.thrust {
		p.speed = min(p.speed + p.accel, p.maxspeed)
		p.thrusting = true
	} else {
		p.speed *= p.friction
	}

	vy := f32(0)
	if in_.up {
		vy = -p.vspeed
	}
	if in_.down {
		vy = p.vspeed
	}
	p.vy = vy
}

player_update :: proc(p: ^Player, g: ^Game, in_: ^Input) {
	p.update_func(p, g, in_)
}

// Camera x that keeps the ship drawn at screen x == p.offset.
player_camera_x :: proc(p: ^Player) -> f32 {
	return p.pos.x - p.offset
}

player_dying :: proc(p: ^Player) -> bool {
	return p.update_func != state_play
}

// Struck by a deadly NPC: begin the death sequence, unless already dying or
// still invulnerable from a respawn.
player_hit :: proc(p: ^Player, g: ^Game) {
	if NODIE || p.invuln > 0 || player_dying(p) {
		return
	}
	push_event(&g.events, {kind = .Player_Hit, pos = p.pos, entity_idx = -1})
	enter_die(p, g)
}

player_fire :: proc(p: ^Player, g: ^Game, in_: ^Input) {
	if in_.fire {
		// draw_texture is top-left anchored: the nose is at the front edge
		// (front in the facing direction) and the vertical centre of the sprite.
		nose_x := p.pos.x + (p.sheet.frame_width / 2) + p.dir*(p.sheet.frame_width/2)
		nose_y := p.pos.y + p.sheet.frame_height/2
		fire_laser(g, nose_x, nose_y, p.dir, abs(p.vx))
	}
}

player_smart_bomb :: proc(p: ^Player, g: ^Game, in_: ^Input) {
	if in_.smart_bomb {
		trigger_smart_bomb(g)
	}
}

// Shared per-frame flight physics: input handling, thrust-lean easing,
// movement, world wrap, vertical clamp, and camera-offset easing. Used by
// both state_play and state_safe_start (the latter counts down to
// state_play underneath, but the player can already fly around while it
// does).
player_move :: proc(p: ^Player, g: ^Game, in_: ^Input) {
	player_handle_input(p, in_)
	player_fire(p, g, in_)
	player_smart_bomb(p, g, in_)

	lean_target := f32(0)
	if p.thrusting {
		lean_target = p.sheet.frame_width
	}
	if p.lean < lean_target {
		p.lean = min(p.lean + p.lean_speed, lean_target)
	} else if p.lean > lean_target {
		p.lean = max(p.lean - p.lean_speed, lean_target)
	}

	if p.invuln > 0 {
		p.invuln -= 1
	}

	p.vx = p.speed * p.dir
	p.pos.x += p.vx
	p.pos.y += p.vy

	if p.pos.x > p.world_width {
		p.pos.x -= p.world_width
	}
	if p.pos.x < 0 {
		p.pos.x += p.world_width
	}

	if p.pos.y < p.top {
		p.pos.y = p.top
	}
	if p.pos.y > p.bottom {
		p.pos.y = p.bottom
	}

	target := p.leftoffset
	if p.dir == -1 {
		target = p.rightoffset
	}
	if p.offset < target {
		p.offset = min(p.offset + OFFSETSPEED, target)
	} else if p.offset > target {
		p.offset = max(p.offset - OFFSETSPEED, target)
	}
}

// --- states ------------------------------------------------------------

// Ship visible, input skipped for exactly the first frame (see the timer
// check below -- that's the one frame SPACE might still be registering as
// having just started the game rather than as a "reverse" command here).
state_safe_start :: proc(p: ^Player, g: ^Game, in_: ^Input) {
	hide_enemies(g)
	freeze_enemies(g)
	if p.timer < SAFE_START_FRAMES {
		player_move(p, g, in_)
	}
	p.timer -= 1
	if p.timer <= 0 {
		enter_play(p, g)
	}
}

enter_play :: proc(p: ^Player, g: ^Game) {
	p.update_func = state_play
	p.invuln = 120
	show_enemies(g)
	unfreeze_enemies(g)
}

// TODO: hyperspace on in_.hyperspace (needs far_from_npcs()).
state_play :: proc(p: ^Player, g: ^Game, in_: ^Input) {
	player_move(p, g, in_)
}

// Frozen in place, flashing red before it blows. Enemies stay visible but
// freeze too.
enter_die :: proc(p: ^Player, g: ^Game) {
	p.update_func = state_die
	p.timer = 120 // 2 seconds, frozen
	p.speed = 0
	p.vx = 0
	p.vy = 0
	p.thrusting = false
	p.lean = 0
	freeze_enemies(g)
	clear_lasers(g)
	clear_bonuses(g)
	deactivate_dying_entities(g)
	push_event(&g.events, {kind = .Player_Die, pos = p.pos, entity_idx = -1})
}

state_die :: proc(p: ^Player, g: ^Game, in_: ^Input) {
	p.timer -= 1
	p.flash = (p.timer / 3) % 2 == 0 // rapid alternation, ~10Hz
	if p.timer <= 0 {
		enter_explode(p, g)
	}
}

// Ship is gone, particle burst plays. Enemies hidden as well as frozen.
enter_explode :: proc(p: ^Player, g: ^Game) {
	p.update_func = state_explode
	p.timer = 150 // 3 seconds before the safe-start window begins
	p.visible = false
	p.flash = false
	hide_enemies(g)
	freeze_enemies(g) // already frozen since enter_die(); stays that way
	clear_bullets(g)
	// burst from the centre of the ship
	explode_at(g, p.pos.x+p.sheet.frame_width/2, p.pos.y+p.sheet.frame_height/2)
	push_event(&g.events, {kind = .Player_Explode, pos = p.pos, entity_idx = -1})
}

state_explode :: proc(p: ^Player, g: ^Game, in_: ^Input) {
	p.timer -= 1
	if p.timer <= 0 {
		enter_safe_start(p, g)
	}
}

enter_safe_start :: proc(p: ^Player, g: ^Game) {
	p.update_func = state_safe_start
	p.timer = SAFE_START_FRAMES
	p.visible = true
	p.flash = false
	p.speed = 0
	p.vx = 0
	p.dir = 1
	p.offset = p.leftoffset
	p.invuln = 0
	push_event(&g.events, {kind = .Player_Start, pos = p.pos, entity_idx = -1})
}

// --- draw ----------------------------------------------------------------

player_draw :: proc(p: ^Player, cam: ^Camera) {
	if !p.visible {
		return
	}
	// blink while invulnerable after a respawn
	if p.invuln > 0 && (p.invuln / 4) % 2 == 0 {
		return
	}
	spos, ok := camera_translate(cam, p.pos.x)
	if !ok {
		return
	}

	// shift the drawn (screen-space only) position by the current lean,
	// forward in the facing direction -- world pos.x is untouched
	draw_x := spos + p.lean*p.dir
	flip := p.dir == -1

	if p.update_func == state_die {
		// death flash: alternate an all-white and an all-red ship. The white
		// silhouette is tinted, so both colours come from one texture.
		tint := COLOUR_WHITE
		if !p.flash {
			tint = COLOUR_RED
		}
		sprite_draw_flip(&p.flash_sheet, draw_x, p.pos.y, tint, flip)
		return
	}

	if p.thrusting {
		// thrust flame: scaled down and offset from the hull by a small gap
		// (not flush against it). Vertically re-centred on the unscaled
		// frame so shrinking it doesn't drift it toward the top.
		flame_w := p.thrust_sheet.frame_width * THRUST_SCALE
		flame_h := p.thrust_sheet.frame_height * THRUST_SCALE
		ty := p.pos.y + (p.thrust_sheet.frame_height - flame_h) / 2
		tx := draw_x - flame_w - THRUST_GAP // facing right: flame left of ship
		if p.dir == -1 {
			tx = draw_x + p.sheet.frame_width + THRUST_GAP // facing left: flame right of ship
		}
		sprite_draw_scaled(&p.thrust_sheet, tx, ty, COLOUR_WHITE, flip, THRUST_SCALE)
	}
	sprite_draw_flip(&p.sheet, draw_x, p.pos.y, COLOUR_WHITE, flip)
}
