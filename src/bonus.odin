package main

import rl "vendor:raylib"

// Floating bonus-score popup, shown when a human is rescued: a "250"/"500"
// flash-cycle graphic that spawns where the human was (just above it) and
// drifts at whatever horizontal speed the player had at that instant --
// not glued to the ship's current position.
//
// Each popup gets its own independent Sprite_Sheet copy rather than
// sharing one per value -- sharing would mean N simultaneous popups of the
// same value call sprite_advance() N times per frame on the same state,
// desyncing/speeding up the flash-cycle with stack depth.
Bonus_Kind :: enum {
	Points_250,
	Points_500,
}

Bonus :: struct {
	active: bool,
	kind:   Bonus_Kind,
	sheet:  Sprite_Sheet,
	vx:     f32, // horizontal drift, captured from the player at spawn time
	life:   int,
	pos:    rl.Vector2,
}

// Scans this frame's event queue for rescue events.
apply_bonus_events :: proc(g: ^Game) {
	for i in 0 ..< g.events.count {
		ev := &g.events.events[i]
		#partial switch ev.kind {
		case .Human_Caught:
			bonus_spawn(g, .Points_500, ev.pos)
		case .Human_Saved:
			bonus_spawn(g, .Points_250, ev.pos)
		}
	}
}

// Spawn a floating "250"/"500" popup at (roughly) the rescued human's
// position, just above it.
bonus_spawn :: proc(g: ^Game, kind: Bonus_Kind, pos: rl.Vector2) {
	idx := -1
	for i in 0 ..< MAX_BONUSES {
		if !g.bonuses[i].active {
			idx = i
			break
		}
	}
	if idx < 0 {
		return // pool exhausted; drop the popup
	}

	tex := g.assets.pts250
	if kind == .Points_500 {
		tex = g.assets.pts500
	}

	b := &g.bonuses[idx]
	b.kind = kind
	b.sheet = make_sprite_sheet(tex, 3, 1, 3)
	sprite_set_animate(&b.sheet, 6)
	b.pos = {pos.x, pos.y - 50}
	b.vx = g.player.vx
	b.life = BONUS_LIFE
	b.active = true
}

update_bonuses :: proc(g: ^Game) {
	for i in 0 ..< MAX_BONUSES {
		b := &g.bonuses[i]
		if !b.active {
			continue
		}
		b.pos.x += b.vx
		if b.pos.x > WORLD_WIDTH {
			b.pos.x -= WORLD_WIDTH
		}
		if b.pos.x < 0 {
			b.pos.x += WORLD_WIDTH
		}
		b.life -= 1
		if b.life <= 0 {
			b.active = false
		}
	}
}

clear_bonuses :: proc(g: ^Game) {
	for i in 0 ..< MAX_BONUSES {
		g.bonuses[i].active = false
	}
}

draw_bonuses :: proc(g: ^Game, cam: ^Camera) {
	for i in 0 ..< MAX_BONUSES {
		b := &g.bonuses[i]
		if !b.active {
			continue
		}
		spos, ok := camera_translate(cam, b.pos.x)
		if !ok {
			continue
		}
		sprite_draw(&b.sheet, {spos, b.pos.y}, COLOUR_WHITE)
	}
}
