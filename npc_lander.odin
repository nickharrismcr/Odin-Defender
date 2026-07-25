package main

import rl "vendor:raylib"

// Lander/mutant: the core "Defender" enemy. State chain: materialize ->
// descend -> search -> grab -> abduct -> mutated -> die. Every transition
// into a state (other than the initial one, set in make_lander) goes
// through a matching lander_enter_<state> function.
//
// Lander has its own die implementation (lander_enter_die/lander_state_die),
// distinct from the generic entity_enter_die/entity_state_die shared by the
// simpler NPC kinds, since its death needs to drop/release any carried
// human.

LANDER_RADAR_GREEN :: rl.Color{0, 200, 0, 255}
LANDER_RADAR_RED :: rl.Color{255, 0, 0, 255}
LANDER_RADAR_BLUE :: rl.Color{0, 0, 255, 255}
LANDER_RADAR_MAGENTA :: rl.Color{255, 0, 255, 255}
MUTANT_RADAR_COLOURS := [4]rl.Color{LANDER_RADAR_RED, LANDER_RADAR_GREEN, LANDER_RADAR_BLUE, LANDER_RADAR_MAGENTA}

make_lander :: proc(a: ^Assets, pos: rl.Vector2) -> Entity {
	e: Entity
	e.active = true
	e.visible = true
	e.kind = .Lander
	e.pos = pos
	e.sheet = make_sprite_sheet(a.lander, 3, 1, 3)
	sprite_set_animate(&e.sheet, 10)
	e.disperse = 50
	e.disperse_rate = 1.3
	e.disperse_max = 60
	e.radar_visible = true
	e.radar_colour = LANDER_RADAR_GREEN
	e.shootable = true
	e.deadly = true
	e.human_idx = -1
	e.lander_state = .Materialize
	e.update_func = lander_state_materialize
	e.draw_func = entity_draw_dispersed
	return e
}

lander_near :: proc(a, b: f32) -> bool {
	return abs(a - b) < 5
}

// Fires a shot aimed at the player, gated by a small random per-frame
// chance. time_mult scales the aim's time-to-target (search() uses a
// slower, more lenient shot while wandering). Never fires while off-screen.
lander_maybe_fire_bullet :: proc(g: ^Game, e: ^Entity, time_mult: f32 = 1.0) {
	_, on_screen := camera_translate(&g.cam, e.pos.x)
	if !on_screen {
		return
	}
	if rand_int(0, 200) == 1 {
		aim_bullet_at(g, e, time_mult)
	}
}

// Shot by a player laser: start the death/explode sequence, unless already
// exploding.
lander_hit :: proc(e: ^Entity, g: ^Game) {
	if e.update_func != lander_state_die {
		lander_enter_die(e, g)
	}
}

// --- states --------------------------------------------------------------

lander_state_materialize :: proc(e: ^Entity, g: ^Game) {
	// converge the dispersed tiles into the assembled sprite (disperse 50 -> 1)
	e.disperse -= 0.7
	if e.disperse <= 1 {
		lander_enter_descend(e, g)
	}
}

lander_enter_descend :: proc(e: ^Entity, g: ^Game) {
	e.disperse = 1
	e.draw_func = entity_draw_normal
	e.dp = {-5, 5}
	e.counter = 0
	e.lander_state = .Descend
	e.update_func = lander_state_descend
}

lander_state_descend :: proc(e: ^Entity, g: ^Game) {
	e.pos += e.dp

	mh := mountains_get(&g.mountains, e.pos.x)
	msh := f32(HEIGHT) - mh

	if e.pos.y > msh-200 {
		lander_enter_search(e, g)
	}

	lander_maybe_fire_bullet(g, e)
}

lander_enter_search :: proc(e: ^Entity, g: ^Game) {
	e.human_idx = pick_a_human(g, e.pos.x)
	e.dp.x = -LANDER_SEARCH_SPEED
	e.dp.y = 0
	e.lander_state = .Search
	e.update_func = lander_state_search
	push_event(&g.events, {kind = .Lander_Searching, pos = e.pos, entity_idx = entity_index(g, e)})
}

lander_state_search :: proc(e: ^Entity, g: ^Game) {
	e.pos += e.dp
	mh := mountains_get(&g.mountains, e.pos.x)
	msh := f32(HEIGHT) - mh
	e.pos.y = msh - 200
	lander_maybe_fire_bullet(g, e, 2.0) // slower, more lenient shot while wandering/searching

	if e.human_idx != -1 {
		h := &g.entities[e.human_idx]
		if h.human_state == .Dying || !h.active {
			e.human_idx = -1 // target died before being grabbed -- find another below
		}
	}

	// Keep retrying every frame while we have no target -- not just when a
	// previously-claimed one dies. The lander is always drifting (and
	// wrapping around the world), so its position keeps changing; without
	// this, failing to find anyone in radius the instant search begins
	// would leave it searching forever, even as it wanders back into range
	// of a human later.
	if e.human_idx == -1 {
		e.human_idx = pick_a_human(g, e.pos.x)
	}

	if e.human_idx != -1 {
		h := &g.entities[e.human_idx]
		if lander_near(h.pos.x, e.pos.x) {
			lander_enter_grab(e, g)
		}
	}
}

lander_enter_grab :: proc(e: ^Entity, g: ^Game) {
	e.dp = {0, 3}
	e.lander_state = .Grab
	e.update_func = lander_state_grab
	// a single decisive shot right at the player the instant it commits to
	// the grab -- but only if on screen (landers should never fire while
	// off-screen)
	_, on_screen := camera_translate(&g.cam, e.pos.x)
	if on_screen {
		aim_bullet_at(g, e, 1.0)
	}
}

lander_state_grab :: proc(e: ^Entity, g: ^Game) {
	e.pos += e.dp
	if e.human_idx == -1 || g.entities[e.human_idx].human_state == .Dying || !g.entities[e.human_idx].active {
		lander_enter_search(e, g) // target died before being grabbed -- find another
		return
	}
	h := &g.entities[e.human_idx]
	if e.pos.y > h.pos.y {
		lander_enter_abduct(e, g)
	}
	lander_maybe_fire_bullet(g, e)
}

lander_enter_abduct :: proc(e: ^Entity, g: ^Game) {
	h := &g.entities[e.human_idx]
	e.pos.y = h.pos.y - 50
	human_grab(g, e.human_idx, entity_index(g, e)) // human now follows this lander
	e.dp.y = -LANDER_ASCEND_SPEED
	e.lander_state = .Abduct
	e.update_func = lander_state_abduct
}

lander_state_abduct :: proc(e: ^Entity, g: ^Game) {
	// the human tracks us itself now (its `grabbed` state), so just ascend
	e.pos.y += e.dp.y
	if e.pos.y < 150 {
		lander_enter_mutated(e, g)
	}
	lander_maybe_fire_bullet(g, e)
}

// May be called with no human ever grabbed (e.g. forced by
// trigger_world_explode() in a later phase), hence the human_idx check.
lander_enter_mutated :: proc(e: ^Entity, g: ^Game) {
	if e.human_idx != -1 {
		human_eat(g, e.human_idx) // the carried human is eaten
		e.human_idx = -1
	}
	e.kind = .Mutant
	e.sheet = make_sprite_sheet(g.assets.mutant, 6, 1, 6)
	sprite_set_animate(&e.sheet, 2)
	e.dp = {0, 0} // aimed at the player every frame in state_mutated
	e.counter = 0
	e.lander_state = .Mutated
	e.update_func = lander_state_mutated
	push_event(&g.events, {kind = .Lander_Mutated, pos = e.pos, entity_idx = entity_index(g, e)})
}

lander_state_mutated :: proc(e: ^Entity, g: ^Game) {
	e.radar_colour = MUTANT_RADAR_COLOURS[rand_int(0, 3)]

	// chase the player horizontally, taking the shorter way around the
	// world wrap rather than a naive x1-x2 (which breaks near the seam)
	mutant_speed := f32(PLAYER_MAXSPEED) * f32(MUTANT_SPEED_PCT)
	dx := shortest_dx(e.pos.x, g.player.pos.x, WORLD_WIDTH)
	e.dp.x = mutant_speed
	if dx < 0 {
		e.dp.x = -mutant_speed
	}
	e.pos += e.dp

	if e.counter % 20 == 0 {
		e.dp.y = -5
		if rand_int(0, 1) == 1 {
			e.dp.y = 5
		}
	}

	if e.pos.y < 100 {
		e.pos.y = 100
		if e.dp.y < 0 {
			e.dp.y = 5
		}
	}
	if e.pos.y > f32(HEIGHT)-40 {
		e.pos.y = f32(HEIGHT) - 40
		if e.dp.y > 0 {
			e.dp.y = -5
		}
	}

	// fixed cadence rather than the random-chance maybe_fire_bullet() other
	// lander states use -- a mutant is already fully hostile and committed
	if e.counter % 60 == 0 {
		_, on_screen := camera_translate(&g.cam, e.pos.x)
		if on_screen {
			aim_bullet_at(g, e, 1.0)
		}
	}
}

lander_enter_die :: proc(e: ^Entity, g: ^Game) {
	e.draw_func = entity_draw_dispersed
	e.disperse = 1
	e.dp = {0, 0}
	e.radar_visible = false
	e.shootable = false
	e.deadly = false
	// if carrying/holding a human, drop a grabbed one, otherwise free a chosen one
	if e.human_idx != -1 {
		h := &g.entities[e.human_idx]
		if h.human_state == .Grabbed {
			human_drop(g, e.human_idx)
		} else {
			human_release(g, e.human_idx)
		}
		e.human_idx = -1
	}
	e.lander_state = .Die
	e.update_func = lander_state_die
	kill_kind := Event_Kind.Lander_Killed
	if e.kind == .Mutant {
		kill_kind = .Mutant_Killed
	}
	push_event(&g.events, {kind = kill_kind, pos = e.pos, entity_idx = entity_index(g, e)})
}

lander_state_die :: proc(e: ^Entity, g: ^Game) {
	// scatter the tiles apart (disperse 1 -> 60), then the entity is gone
	e.disperse += e.disperse_rate
	if e.disperse >= e.disperse_max {
		e.active = false // release the pool slot
	}
}
