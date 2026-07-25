package main

import rl "vendor:raylib"

// Floating bonus-score popup, shown when a human is rescued: a "250"/"500"
// flash-cycle graphic that spawns above the player and tracks it for its
// whole life.
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
	dy:     f32, // vertical offset above the player; staggers stacked popups
	life:   int,
	pos:    rl.Vector2,
}

// Scans this frame's event queue for rescue events.
apply_bonus_events :: proc(g: ^Game) {
	for i in 0 ..< g.events.count {
		#partial switch g.events.events[i].kind {
		case .Human_Caught:
			bonus_spawn(g, .Points_500)
		case .Human_Saved:
			bonus_spawn(g, .Points_250)
		}
	}
}

bonus_active_count :: proc(g: ^Game) -> int {
	n := 0
	for i in 0 ..< MAX_BONUSES {
		if g.bonuses[i].active {
			n += 1
		}
	}
	return n
}

// Spawn a floating "250"/"500" popup. Stacks multiple simultaneous popups
// above the ship rather than overlapping.
bonus_spawn :: proc(g: ^Game, kind: Bonus_Kind) {
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

	count := bonus_active_count(g) // BEFORE this slot is marked active

	tex := g.assets.pts250
	if kind == .Points_500 {
		tex = g.assets.pts500
	}

	b := &g.bonuses[idx]
	b.kind = kind
	b.sheet = make_sprite_sheet(tex, 3, 1, 3)
	sprite_set_animate(&b.sheet, 6)
	b.dy = -60 - f32(count)*24
	b.life = BONUS_LIFE
	b.pos = {0, 0}
	b.active = true
}

update_bonuses :: proc(g: ^Game) {
	for i in 0 ..< MAX_BONUSES {
		b := &g.bonuses[i]
		if !b.active {
			continue
		}
		// centred horizontally on the ship
		b.pos.x = g.player.pos.x + g.player.sheet.frame_width/2 - b.sheet.frame_width/2
		b.pos.y = g.player.pos.y + b.dy
		b.life -= 1
		if b.life <= 0 {
			b.active = false
		}
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
