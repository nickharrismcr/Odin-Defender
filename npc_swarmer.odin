package main

import rl "vendor:raylib"

// Swarmer: released when a pod is destroyed. Homes in on the player at
// speed, re-aiming several times a second, and occasionally fires.
make_swarmer :: proc(a: ^Assets, pos: rl.Vector2) -> Entity {
	e: Entity
	e.active = true
	e.visible = true
	e.kind = .Swarmer
	e.pos = pos
	e.sheet = make_sprite_sheet(a.swarmer, 1, 1, 1) // swarmer.png = single 20x16 frame
	e.disperse = 1
	e.radar_visible = true
	e.radar_colour = rl.Color{255, 80, 0, 255}
	e.shootable = true
	e.deadly = true
	e.maxspeed = rand_f32(13.0, 17.0)
	e.nextthink = 0

	// disperse rises by disperse_rate each frame up to disperse_max, over
	// ~3 seconds, so swarmers burst apart at varying spreads
	ddisp := rand_f32(10.0, 50.0)
	e.disperse_rate = ddisp / 60.0
	e.disperse_max = ddisp * 3

	e.update_func = swarmer_state_chase
	e.draw_func = entity_draw_normal
	return e
}

swarmer_state_chase :: proc(e: ^Entity, g: ^Game) {
	e.nextthink -= 1
	if e.nextthink < 0 {
		e.dp = seek_player(g, e, e.maxspeed, 60, f32(rand_int(-500, 500)), f32(rand_int(-300, 300)))
		e.nextthink = 12 // re-aim every 0.2s
		if e.counter > 60 && rand_int(0, 100) == 1 {
			aim_bullet_at(g, e, 1.0)
		}
	}
	e.pos += e.dp

	// keep inside the play area vertically
	if e.pos.y < 110 {
		e.pos.y = 110
	}
	if e.pos.y > f32(HEIGHT)-40 {
		e.pos.y = f32(HEIGHT) - 40
	}
}
