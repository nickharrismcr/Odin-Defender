package main

import rl "vendor:raylib"

// Pod: hangs motionless until shot, then bursts into a cluster of swarmers.
// Ported from npc/pod.lox.
make_pod :: proc(a: ^Assets, pos: rl.Vector2) -> Entity {
	e: Entity
	e.active = true
	e.visible = true
	e.kind = .Pod
	e.pos = pos
	e.sheet = make_sprite_sheet(a.pod, 2, 1, 2) // pod.png = 2 frames of 28x28
	sprite_set_animate(&e.sheet, 20)
	e.disperse = 1
	e.disperse_rate = 1.3
	e.disperse_max = 60
	e.radar_visible = true
	e.radar_colour = COLOUR_MAGENTA
	e.shootable = true
	e.deadly = true
	e.update_func = pod_state_drift
	e.draw_func = entity_draw_normal
	return e
}

pod_state_drift :: proc(e: ^Entity, g: ^Game) {
	// pods hang motionless
}
