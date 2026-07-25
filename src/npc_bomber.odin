package main

import rl "vendor:raylib"

// Bomber: drifts diagonally, bouncing off the top and bottom of the play
// area, scattering bombs as it goes.
make_bomber :: proc(a: ^Assets, pos: rl.Vector2) -> Entity {
	e: Entity
	e.active = true
	e.visible = true
	e.kind = .Bomber
	e.pos = pos
	e.sheet = make_sprite_sheet(a.bomber, 3, 1, 3)
	sprite_set_animate(&e.sheet, 8)
	e.disperse = 1
	e.disperse_rate = 1.3
	e.disperse_max = 60
	e.radar_visible = true
	e.radar_colour = rl.Color{0, 150, 255, 255}
	e.shootable = true
	e.deadly = true
	e.dp = {1.7, 1.7} // ~100 px/s each axis, at 60fps
	e.update_func = bomber_state_bomb
	e.draw_func = entity_draw_normal
	return e
}

bomber_state_bomb :: proc(e: ^Entity, g: ^Game) {
	e.pos += e.dp

	// bounce off the ceiling / floor of the play area
	if e.pos.y < PLAYER_TOP {
		e.pos.y = PLAYER_TOP
		e.dp.y = -e.dp.y
	}
	if e.pos.y > f32(HEIGHT)-60 {
		e.pos.y = f32(HEIGHT) - 60
		e.dp.y = -e.dp.y
	}

	// ~1 in 20 chance per frame of dropping a bomb.
	if rand_int(0, 100) < 5 {
		// dropped bombs sit where they land (zero velocity) and auto-expire
		// via ticks_to_live, with double the usual bullet lifetime, so they
		// linger as hazards.
		fire_bullet(g, e.pos, {0, 0}, 200)
	}
}
