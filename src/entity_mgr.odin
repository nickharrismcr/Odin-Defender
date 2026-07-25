package main

import rl "vendor:raylib"

// Scalar/manager-level state for the entity subsystem -- fields that don't
// belong to any single entity or pool.
Entity_Mgr_State :: struct {
	landers_alive:    int,
	baiter_timer:     int,
	max_baiters:      int, // set by apply_level (config.odin) at each level_start
	swarmers_per_pod: int,
	humans_left:      int,
	world_exploding:  bool,
	bombs:            int,
	bomb_pending:     int,
	bomb_flash:       int,
	enemies_hidden:   bool, // draw() skips non-human entities while true
	frozen:           bool, // update()/check_collisions() no-op while true
	laser_colour_idx: int,
	npc_bullet_time:  int, // set by apply_level (config.odin) at each level_start
}

init_entity_mgr :: proc() -> Entity_Mgr_State {
	m: Entity_Mgr_State
	m.swarmers_per_pod = SWARMERS_PER_POD
	m.baiter_timer = BAITER_DELAY
	m.max_baiters = 1
	m.bombs = STARTING_BOMBS
	m.npc_bullet_time = NPC_BULLET_TIME_BASE
	return m
}

// Set/cleared directly by Player's own enter_/state_ functions as it moves
// through its states -- not event-driven, since the coupling is tight
// enough that it's clearer to read at the call site. See player.odin.
hide_enemies :: proc(g: ^Game) {
	g.mgr.enemies_hidden = true
}
show_enemies :: proc(g: ^Game) {
	g.mgr.enemies_hidden = false
}
freeze_enemies :: proc(g: ^Game) {
	g.mgr.frozen = true
}
unfreeze_enemies :: proc(g: ^Game) {
	g.mgr.frozen = false
}

fire_bullet :: proc(g: ^Game, p, v: rl.Vector2, life: int = 100) {
	bullet_pool_fire(g, p, v, life)
	push_event(&g.events, {kind = .Bullet_Fire, pos = p, entity_idx = -1})
}

fire_laser :: proc(g: ^Game, x, y, dir, speed: f32) {
	laser_pool_fire(g, x, y, dir, speed)
	push_event(&g.events, {kind = .Laser_Fire, pos = {x, y}, entity_idx = -1})
}

// One-shot explosion burst at a world position.
explode_at :: proc(g: ^Game, x, y: f32) {
	emit_burst(g, x, y, EXPLOSION_PARTICLES)
}

// Removes every non-human entity, clears the spawn queue, and kills every
// active bullet/laser -- used at the end of a level so nothing lingers on
// screen behind the level-complete banner. Humans persist across levels.
clear_wave :: proc(g: ^Game) {
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if e.active && e.kind != .Human {
			e.active = false
		}
	}
	for i in 0 ..< MAX_PENDING_SPAWNS {
		g.spawn_queue[i].active = false
	}
	clear_bullets(g)
	clear_lasers(g)
}

// Baiters currently in play: alive plus queued-but-not-yet-materialised.
baiter_count :: proc(g: ^Game) -> int {
	n := 0
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if e.active && e.kind == .Baiter {
			n += 1
		}
	}
	for i in 0 ..< MAX_PENDING_SPAWNS {
		ps := &g.spawn_queue[i]
		if ps.active && ps.kind == .Baiter {
			n += 1
		}
	}
	return n
}

// Send in a baiter every baiter_delay frames once the landers are nearly
// cleared, up to max_baiters simultaneously.
update_baiters :: proc(g: ^Game) {
	if g.mgr.baiter_timer > BAITER_DELAY {
		g.mgr.baiter_timer = BAITER_DELAY
	}
	gated := g.mgr.landers_alive <= BAITER_THRESHOLD && baiter_count(g) < g.mgr.max_baiters
	if gated {
		g.mgr.baiter_timer -= 1
		if g.mgr.baiter_timer <= 0 {
			add_baiter(g, 0)
			g.mgr.baiter_timer = BAITER_DELAY
		}
	} else {
		g.mgr.baiter_timer = BAITER_DELAY
	}
}

// Backspace: kill every enemy on screen (humans are spared), twice in quick
// succession -- the second pass catches swarmers released by any pod killed
// in the first. A no-op once bombs run out.
trigger_smart_bomb :: proc(g: ^Game) {
	if g.mgr.bombs <= 0 {
		return
	}
	g.mgr.bombs -= 1
	smart_bomb_pass(g)
	g.mgr.bomb_pending = BOMB_PASS_DELAY
}

smart_bomb_pass :: proc(g: ^Game) {
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active || e.kind == .Human {
			continue
		}
		if _, on_screen := camera_translate(&g.cam, e.pos.x); on_screen {
			entity_hit(e, g)
		}
	}
	g.mgr.bomb_flash = BOMB_FLASH_FRAMES
}

// All humans are gone: force every actively-hunting lander to mutate
// immediately (landers not yet actively engaged are just removed, no death
// animation -- already-dying landers are left alone), and start the
// mountains crumbling for the rest of the game. Mutated landers have
// kind==Mutant, already excluded by the kind filter below.
trigger_world_explode :: proc(g: ^Game) {
	mountains_explode(&g.mountains)
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active || e.kind != .Lander {
			continue
		}
		f := e.update_func
		if f == lander_state_search || f == lander_state_grab || f == lander_state_abduct {
			lander_enter_mutated(e, g)
		} else if f != lander_state_die {
			e.active = false
		}
	}
	push_event(&g.events, {kind = .No_Humans, entity_idx = -1})
}

// No-ops while the player's death sequence plays out -- everything freezes
// in place until it respawns.
update_entity_mgr :: proc(g: ^Game) {
	if g.mgr.frozen {
		return
	}

	g.mgr.landers_alive = 0
	g.mgr.humans_left = 0

	tick_spawn_queue(g)
	update_entities(g)

	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active {
			continue
		}
		if e.kind == .Human {
			g.mgr.humans_left += 1
		}
		if e.kind == .Lander {
			g.mgr.landers_alive += 1
		}
	}

	mountains_update(&g.mountains)
	update_bullets(g)
	update_lasers(g)
	update_bonuses(g)
	update_baiters(g)

	if g.mgr.bomb_pending > 0 {
		g.mgr.bomb_pending -= 1
		if g.mgr.bomb_pending <= 0 {
			smart_bomb_pass(g)
		}
	}
	if g.mgr.bomb_flash > 0 {
		g.mgr.bomb_flash -= 1
	}

	if g.mgr.humans_left <= 0 && !g.mgr.world_exploding {
		g.mgr.world_exploding = true
		trigger_world_explode(g)
	}
}

// Player lasers destroy shootable NPCs; deadly NPCs hit the player, and
// ramming one kills it right back. Driven by per-entity flags rather than
// kind, so every NPC (and a mutated lander) takes part without special-
// casing. cam is used so the laser only damages NPCs that are actually on
// screen.
check_collisions :: proc(g: ^Game) {
	if g.mgr.frozen {
		return
	}

	pbox := entity_box(g.player.pos, g.player.sheet.frame_width, g.player.sheet.frame_height)

	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active || !(e.shootable || e.deadly) {
			continue
		}
		ebox := entity_box(e.pos, e.sheet.frame_width, e.sheet.frame_height)

		if e.shootable {
			if _, on_screen := camera_translate(&g.cam, e.pos.x); on_screen {
				for j in 0 ..< MAX_LASERS {
					l := &g.lasers[j]
					if l.active && overlap(laser_box(l.pos, l.len), ebox, WORLD_WIDTH) {
						laser_kill(l) // consumed by this hit -- can't punch through to another NPC
						entity_hit(e, g)
					}
				}
			}
		}

		// hit() clears `deadly`, so an already-dying NPC can't also kill the player
		if e.deadly && overlap(pbox, ebox, WORLD_WIDTH) {
			was_dying := player_dying(&g.player)
			player_hit(&g.player, g)
			entity_hit(e, g)
			// If this collision is what actually killed the player (not just
			// a graze while already invulnerable/dying), remove the entity
			// outright rather than let it play out its own disperse-death
			// animation -- that would otherwise sit frozen for the whole
			// death sequence, since freeze_enemies() pauses every entity
			// together. entity_hit already ran its normal death handling
			// (on_die side effects like a pod's swarmers), so nothing is
			// skipped, it just finishes instantly instead of over several
			// frames.
			if !was_dying && player_dying(&g.player) {
				e.active = false
			}
		}
	}

	// NPC bullets die when they strike the player (and damage it).
	for i in 0 ..< MAX_BULLETS {
		b := &g.bullets[i]
		if !bullet_dead(b) {
			bbox := entity_box(b.pos, b.sheet.frame_width, b.sheet.frame_height)
			if overlap(bbox, pbox, WORLD_WIDTH) {
				bullet_kill(b)
				player_hit(&g.player, g)
			}
		}
	}

	// the player scoops up a falling human on contact
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if e.active && e.kind == .Human && e.human_state == .Dropping {
			ebox := entity_box(e.pos, e.sheet.frame_width, e.sheet.frame_height)
			if overlap(ebox, pbox, WORLD_WIDTH) {
				human_catch_by(g, i)
			}
		}
	}
}

draw_bomb_flash :: proc(g: ^Game) {
	if g.mgr.bomb_flash > 0 {
		alpha := u8(255.0 * f32(g.mgr.bomb_flash) / f32(BOMB_FLASH_FRAMES))
		rl.DrawRectangle(0, 0, WIDTH, HEIGHT, rl.Color{255, 255, 255, alpha})
	}
}
