package main

import rl "vendor:raylib"

// Temporary manual-test harness for exercising the full entity roster
// before game_controller (Phase 6) drives real level-based spawning.
//   L - spawn a fresh wave of landers near the player
//   K - kill the nearest lander/mutant
//   H - spawn a few humans nearby
//   P - spawn a pod near the player (shoot it to release swarmers)
//   B - spawn a bomber
//   X - trigger an explosion burst at the player's position (particle FX
//       test, without needing to actually die first)
//   J - instantly kill every NPC (including ones still waiting in the
//       spawn queue), to test level-end/the human tally without playing
//       out a whole wave
// Mash these (plus real fire/smart-bomb) to confirm pooling, weapons, and
// collisions all hold up without ever crashing/running out.
debug_update :: proc(g: ^Game) {
	if rl.IsKeyPressed(.L) {
		debug_spawn_landers(g, g.player.pos.x)
	}
	if rl.IsKeyPressed(.K) {
		debug_kill_nearest_lander(g)
	}
	if rl.IsKeyPressed(.H) {
		debug_spawn_humans(g, g.player.pos.x)
	}
	if rl.IsKeyPressed(.P) {
		add_pods(g, 1, g.player.pos.x)
	}
	if rl.IsKeyPressed(.B) {
		add_bombers(g, 1)
	}
	if rl.IsKeyPressed(.X) {
		explode_at(g, g.player.pos.x, g.player.pos.y)
	}
	if rl.IsKeyPressed(.J) {
		debug_kill_all_npcs(g)
	}
}

debug_spawn_landers :: proc(g: ^Game, cx: f32) {
	for _ in 0 ..< 3 {
		x := cx + f32(rand_int(-300, 300))
		pos := rl.Vector2{x, f32(rand_int(120, HEIGHT / 2))}
		queue_spawn(g, .Lander, pos, rand_int(0, 90))
	}
}

// Spawns humans near the player rather than at fully random world-x (the
// original always spawns world-random via add_humans) -- purely so they're
// visible/reachable during manual testing without having to fly for miles.
debug_spawn_humans :: proc(g: ^Game, cx: f32) {
	for _ in 0 ..< 3 {
		x := cx + f32(rand_int(-400, 400))
		queue_spawn(g, .Human, {x, HEIGHT}, 0)
	}
}

debug_kill_nearest_lander :: proc(g: ^Game) {
	best := -1
	best_d := max(f32)
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active || e.dying {
			continue
		}
		if e.kind != .Lander && e.kind != .Mutant {
			continue
		}
		d := abs(shortest_dx(g.player.pos.x, e.pos.x, WORLD_WIDTH))
		if d < best_d {
			best_d = d
			best = i
		}
	}
	if best >= 0 {
		lander_hit(&g.entities[best], g)
	}
}

// Kills every active NPC (landers/pods/swarmers/baiters/bombers -- humans
// spared), and also promotes-then-kills any lander still waiting in the
// spawn queue, so a single press reliably finishes the level regardless of
// wave-stagger delays.
debug_kill_all_npcs :: proc(g: ^Game) {
	for i in 0 ..< MAX_PENDING_SPAWNS {
		ps := &g.spawn_queue[i]
		if ps.active && ps.kind == .Lander {
			promote_spawn(g, ps)
			ps.active = false
		}
	}
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active || e.dying || e.kind == .Human {
			continue
		}
		entity_hit(e, g)
	}
}
