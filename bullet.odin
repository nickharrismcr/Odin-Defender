package main

import rl "vendor:raylib"

// A single NPC bullet/bomb (the same struct is reused for both -- a dropped
// bomb is just a bullet with zero velocity and double lifetime). Pool
// occupancy is implicit in ticks_to_live, matching the original exactly
// (no separate "active" flag -- bullet_dead() IS the pool's free-slot test).
Bullet :: struct {
	pos, dp:       rl.Vector2,
	ticks_to_live: int,
	sheet:         Sprite_Sheet,
}

bullet_dead :: proc(b: ^Bullet) -> bool {
	return b.ticks_to_live <= 0
}

bullet_kill :: proc(b: ^Bullet) {
	b.ticks_to_live = 0
}

init_bullet_pool :: proc(g: ^Game) {
	for i in 0 ..< MAX_BULLETS {
		g.bullets[i].sheet = make_sprite_sheet(g.assets.bullet, 2, 1, 2)
		sprite_set_animate(&g.bullets[i].sheet, 10)
	}
}

// bullet_pool_fire scans for the first dead (free) slot and reuses it.
// Pool-level primitive -- see fire_bullet() in entity_mgr.odin for the
// manager-level wrapper NPCs actually call.
bullet_pool_fire :: proc(g: ^Game, p, v: rl.Vector2, life: int) {
	for i in 0 ..< MAX_BULLETS {
		b := &g.bullets[i]
		if bullet_dead(b) {
			b.pos = p
			b.dp = v
			b.ticks_to_live = life
			return
		}
	}
}

update_bullets :: proc(g: ^Game) {
	for i in 0 ..< MAX_BULLETS {
		b := &g.bullets[i]
		if bullet_dead(b) {
			continue
		}
		b.pos += b.dp
		b.ticks_to_live -= 1
		if b.pos.y < 100 || b.pos.y > HEIGHT {
			b.ticks_to_live = 0
		}
	}
}

draw_bullets :: proc(g: ^Game, cam: ^Camera) {
	for i in 0 ..< MAX_BULLETS {
		b := &g.bullets[i]
		if bullet_dead(b) {
			continue
		}
		spos, ok := camera_translate(cam, b.pos.x)
		if !ok {
			continue
		}
		sprite_draw(&b.sheet, {spos, b.pos.y}, COLOUR_WHITE)
	}
}

clear_bullets :: proc(g: ^Game) {
	for i in 0 ..< MAX_BULLETS {
		bullet_kill(&g.bullets[i])
	}
}
