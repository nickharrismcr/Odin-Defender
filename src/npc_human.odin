package main

import rl "vendor:raylib"

// Human colonist. States: walking (default) -> grabbed (a lander has it) ->
// dropping (carrier killed, falls under gravity) -> dying (fatal drop) or
// walking (survived) -- OR walking -> [player scoops it up while dropping]
// -> caught (rides below the ship) -> walking. eaten (carrier mutated) is a
// terminal, instant loss with no animation.
//
// `human_state` is readable across module boundaries -- the lander and
// check_collisions both test it directly.

make_human :: proc(a: ^Assets, pos: rl.Vector2) -> Entity {
	e: Entity
	e.active = true
	e.visible = true
	e.kind = .Human
	e.pos = pos
	e.sheet = make_sprite_sheet(a.human, 1, 1, 1)
	e.disperse = 1
	e.radar_visible = true
	e.radar_colour = COLOUR_GRAY
	e.shootable = true // humans can be shot by mistake
	e.deadly = false
	e.chosen = false
	e.human_state = .Walking
	e.carrier_kind = .None
	e.carrier_idx = -1
	// dp.x doubles as the walk-direction field (no other velocity use for humans)
	e.dp.x = -1
	if rand_int(0, 1) == 1 {
		e.dp.x = 1
	}
	e.update_func = human_state_walk
	e.draw_func = entity_draw_normal
	return e
}

human_ground_y :: proc(g: ^Game, x: f32) -> f32 {
	return f32(HEIGHT) - mountains_get(&g.mountains, x)
}

// shot by a player laser: start the death/explode sequence, unless already exploding.
human_hit :: proc(e: ^Entity, g: ^Game) {
	if e.human_state != .Dying {
		human_enter_dying(e, g)
	}
}

// --- transitions, driven by the lander / entity manager -------------------

// a lander latched on
human_grab :: proc(g: ^Game, human_idx: int, carrier_idx: int) {
	e := &g.entities[human_idx]
	e.carrier_kind = .Lander
	e.carrier_idx = carrier_idx
	e.chosen = true
	human_enter_grabbed(e, g)
}

// the carrier was killed
human_drop :: proc(g: ^Game, human_idx: int) {
	e := &g.entities[human_idx]
	e.carrier_kind = .None
	e.carrier_idx = -1
	human_enter_dropping(e, g)
}

// the player scooped it up mid-fall
human_catch_by :: proc(g: ^Game, human_idx: int) {
	e := &g.entities[human_idx]
	e.carrier_kind = .Player
	e.carrier_idx = -1
	human_enter_caught(e, g)
}

// the carrier mutated; lost instantly (no death animation)
human_eat :: proc(g: ^Game, human_idx: int) {
	e := &g.entities[human_idx]
	if !e.active {
		return
	}
	e.human_state = .Eaten
	e.active = false
}

// a lander that had chosen but not yet grabbed this human died: free it up
human_release :: proc(g: ^Game, human_idx: int) {
	e := &g.entities[human_idx]
	e.chosen = false
	e.carrier_kind = .None
	e.carrier_idx = -1
}

// --- states ----------------------------------------------------------------

human_state_walk :: proc(e: ^Entity, g: ^Game) {
	if e.counter % 10 == 0 {
		e.pos.x += e.dp.x
		e.pos.y = human_ground_y(g, e.pos.x)
	}
}

human_enter_grabbed :: proc(e: ^Entity, g: ^Game) {
	e.human_state = .Grabbed
	e.update_func = human_state_grabbed
	push_event(&g.events, {kind = .Human_Grabbed, pos = e.pos, entity_idx = entity_index(g, e)})
}

human_state_grabbed :: proc(e: ^Entity, g: ^Game) {
	// hang centred below the carrier lander (sprites are top-left anchored,
	// so the lander's own centre is offset by half its width) as it lifts us
	if e.carrier_kind == .Lander && e.carrier_idx != -1 {
		c := &g.entities[e.carrier_idx]
		e.pos.x = c.pos.x + c.sheet.frame_width/2 - e.sheet.frame_width/2
		e.pos.y = c.pos.y + 30
	}
}

human_enter_dropping :: proc(e: ^Entity, g: ^Game) {
	e.human_state = .Dropping
	e.dp.y = 0
	e.drop_start_y = e.pos.y
	e.update_func = human_state_dropping
	push_event(&g.events, {kind = .Human_Dropped, pos = e.pos, entity_idx = entity_index(g, e)})
}

human_state_dropping :: proc(e: ^Entity, g: ^Game) {
	e.dp.y += HUMAN_DROP_ACCEL // gravity
	e.pos.y += e.dp.y
	ground := human_ground_y(g, e.pos.x)
	if e.pos.y >= ground {
		e.pos.y = ground
		if e.drop_start_y < f32(HEIGHT)/3 {
			human_enter_dying(e, g) // dropped from above the middle: fatal
		} else {
			human_enter_walking(e, g) // survived the fall
		}
	}
}

human_enter_caught :: proc(e: ^Entity, g: ^Game) {
	e.human_state = .Caught
	e.update_func = human_state_caught
	// Bonus (points popup) and Score both react to this via the event queue
	// -- see apply_bonus_events()/update_score() in game.odin.
	push_event(&g.events, {kind = .Human_Caught, pos = e.pos, entity_idx = entity_index(g, e)})
}

human_state_caught :: proc(e: ^Entity, g: ^Game) {
	// ride below the ship until we reach the ground, then walk free
	if e.carrier_kind == .Player {
		e.pos.x = g.player.pos.x
		e.pos.y = g.player.pos.y + 40
	}
	if e.pos.y >= human_ground_y(g, e.pos.x) {
		e.pos.y = human_ground_y(g, e.pos.x)
		human_enter_walking(e, g)
	}
}

// Reached the ground safely, whether unaided (from dropping) or carried down
// by the player (from caught) -- both lead here, so the outcome is shared.
human_enter_walking :: proc(e: ^Entity, g: ^Game) {
	e.chosen = false // no longer a child of a lander/the player ship
	e.carrier_kind = .None
	e.carrier_idx = -1
	e.human_state = .Walking
	e.update_func = human_state_walk
	// Bonus (points popup) and Score both react to this via the event queue
	// -- see apply_bonus_events()/update_score() in game.odin.
	push_event(&g.events, {kind = .Human_Saved, pos = e.pos, entity_idx = entity_index(g, e)})
}

human_enter_dying :: proc(e: ^Entity, g: ^Game) {
	e.draw_func = entity_draw_dispersed
	e.human_state = .Dying
	e.disperse = 1
	e.dp = {0, 0}
	e.radar_visible = false
	e.shootable = false
	e.deadly = false
	e.update_func = human_state_dying
	push_event(&g.events, {kind = .Human_Killed, pos = e.pos, entity_idx = entity_index(g, e)})
}

human_state_dying :: proc(e: ^Entity, g: ^Game) {
	e.disperse += 1.3
	if e.disperse >= 60 {
		e.active = false
	}
}
