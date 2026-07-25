package main

import rl "vendor:raylib"

// Baiter: lurks unseen, then materialises next to the player and hunts it
// down. Ported from npc/baiter.lox.
make_baiter :: proc(a: ^Assets, pos: rl.Vector2, wait_frames: int) -> Entity {
	e: Entity
	e.active = true
	e.kind = .Baiter
	e.pos = pos
	e.sheet = make_sprite_sheet(a.baiter, 2, 1, 2) // baiter.png = 2 frames of 44x16
	sprite_set_animate(&e.sheet, 10)
	e.disperse = 1
	e.disperse_rate = 1.3
	e.disperse_max = 60
	e.radar_visible = true
	e.radar_colour = COLOUR_GREEN
	e.wait_frames = wait_frames
	e.x_to_player = 0
	e.nextthink = 0
	e.maxspeed = 33.0

	// hidden and harmless until it materialises
	e.visible = false
	e.shootable = false
	e.deadly = false

	e.update_func = baiter_state_wait
	e.draw_func = entity_draw_normal
	return e
}

baiter_state_wait :: proc(e: ^Entity, g: ^Game) {
	if e.counter < e.wait_frames {
		return
	}
	baiter_enter_materialize(e, g)
}

// Pop into existence somewhere near the player.
baiter_enter_materialize :: proc(e: ^Entity, g: ^Game) {
	e.x_to_player = f32(rand_int(-500, 500))
	e.pos.y = f32(rand_int(200, HEIGHT-100))
	e.disperse = 50
	e.visible = true
	e.draw_func = entity_draw_dispersed
	e.update_func = baiter_state_materialize
}

baiter_state_materialize :: proc(e: ^Entity, g: ^Game) {
	// re-anchors x to the player every frame while coalescing
	e.pos.x = g.player.pos.x + e.x_to_player
	e.disperse -= 0.67
	if e.disperse <= 1 {
		e.disperse = 1
		baiter_enter_chase(e, g)
	}
}

baiter_enter_chase :: proc(e: ^Entity, g: ^Game) {
	e.draw_func = entity_draw_normal
	e.update_func = baiter_state_chase
	e.shootable = true
	e.deadly = true
	e.nextthink = 0
}

baiter_state_chase :: proc(e: ^Entity, g: ^Game) {
	e.nextthink -= 1
	if e.nextthink < 0 {
		e.dp = seek_player(g, e, e.maxspeed, 60, f32(rand_int(-200, 0)), f32(rand_int(-100, 100)))
		e.nextthink = 30 // re-aim every 0.5s
	}
	e.pos += e.dp

	if e.pos.y < 110 {
		e.pos.y = 110
	}
	if e.pos.y > f32(HEIGHT)-40 {
		e.pos.y = f32(HEIGHT) - 40
	}

	if rand_int(0, 150) == 1 {
		aim_bullet_at(g, e, 1.0)
	}
}
