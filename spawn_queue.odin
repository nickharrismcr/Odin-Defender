package main

import rl "vendor:raylib"

// Fixed-capacity replacement for the original's dynamic [entity,delay] list
// (entity_mgr.lox's this.queue). Position/params are resolved at enqueue
// time, matching the original.
Spawn_Kind :: enum {
	Lander,
	Pod,
	Swarmer,
	Baiter,
	Bomber,
	Human,
}

Pending_Spawn :: struct {
	active:      bool,
	kind:        Spawn_Kind,
	delay:       int,
	pos:         rl.Vector2,
	wait_frames: int, // baiter only
}

queue_spawn :: proc(g: ^Game, kind: Spawn_Kind, pos: rl.Vector2, delay: int, wait_frames: int = 0) {
	for i in 0 ..< MAX_PENDING_SPAWNS {
		if !g.spawn_queue[i].active {
			g.spawn_queue[i] = Pending_Spawn {
				active      = true,
				kind        = kind,
				pos         = pos,
				delay       = delay,
				wait_frames = wait_frames,
			}
			return
		}
	}
	// Pool exhausted: matches the original's pools, which silently drop a
	// spawn/fire attempt when full rather than growing. See the porting
	// plan's note on adding a loud debug assert here if this ever proves
	// reachable in real play.
}

// add_landers queues `num` landers with world-random spawn positions,
// staggered `delay` frames apart from being called. Ported from
// EntityMgr.add_landers().
add_landers :: proc(g: ^Game, num, delay: int) {
	for _ in 0 ..< num {
		pos := rl.Vector2{f32(rand_int(0, WORLD_WIDTH)), f32(rand_int(100, HEIGHT / 2))}
		queue_spawn(g, .Lander, pos, delay)
	}
}

// Spawn a single lander near world-x cx, so at least one materialises within
// the player's view rather than somewhere off in the 10k-wide world.
add_lander_near :: proc(g: ^Game, cx: f32, delay: int) {
	x := cx + f32(rand_int(-60, 60))
	pos := rl.Vector2{x, f32(rand_int(120, HEIGHT / 2))}
	queue_spawn(g, .Lander, pos, delay)
}

// Pods drift near the player, waiting to be shot open.
add_pods :: proc(g: ^Game, num: int, cx: f32) {
	for _ in 0 ..< num {
		x := cx + f32(rand_int(0, 1500))
		y := f32(rand_int(int(PLAYER_TOP), HEIGHT - 400))
		queue_spawn(g, .Pod, {x, y}, 0)
	}
}

// Released when a pod is destroyed; they burst out from the pod's position.
add_swarmers :: proc(g: ^Game, num: int, x, y: f32) {
	for _ in 0 ..< num {
		pos := rl.Vector2{x + f32(rand_int(-20, 20)), y + f32(rand_int(-20, 20))}
		queue_spawn(g, .Swarmer, pos, 0)
	}
}

add_bombers :: proc(g: ^Game, num: int) {
	for _ in 0 ..< num {
		x := f32(rand_int(0, WORLD_WIDTH))
		y := f32(rand_int(int(PLAYER_TOP), HEIGHT - 200))
		queue_spawn(g, .Bomber, {x, y}, 0)
	}
}

// A baiter lurks invisibly, then materialises next to the player.
add_baiter :: proc(g: ^Game, wait_frames: int) {
	queue_spawn(g, .Baiter, {0, 0}, 0, wait_frames)
}

add_humans :: proc(g: ^Game, num: int) {
	for _ in 0 ..< num {
		pos := rl.Vector2{f32(rand_int(0, WORLD_WIDTH)), f32(HEIGHT)}
		queue_spawn(g, .Human, pos, 0)
	}
}

// Ticks every pending spawn's delay down by one, promoting any that reach
// zero into a live pool entity. Ported from EntityMgr.update()'s queue-drain
// loop.
tick_spawn_queue :: proc(g: ^Game) {
	for i in 0 ..< MAX_PENDING_SPAWNS {
		ps := &g.spawn_queue[i]
		if !ps.active {
			continue
		}
		ps.delay -= 1
		if ps.delay <= 0 {
			promote_spawn(g, ps)
			ps.active = false
		}
	}
}

promote_spawn :: proc(g: ^Game, ps: ^Pending_Spawn) {
	idx := acquire_entity(g)
	if idx < 0 {
		return // entity pool exhausted; drop the spawn (see acquire_entity)
	}
	spawn_kind: Event_Kind
	switch ps.kind {
	case .Lander:
		g.entities[idx] = make_lander(&g.assets, ps.pos)
		spawn_kind = .Lander_Spawn
	case .Pod:
		g.entities[idx] = make_pod(&g.assets, ps.pos)
		spawn_kind = .Pod_Spawn
	case .Swarmer:
		g.entities[idx] = make_swarmer(&g.assets, ps.pos)
		spawn_kind = .Swarmer_Spawn
	case .Baiter:
		g.entities[idx] = make_baiter(&g.assets, ps.pos, ps.wait_frames)
		spawn_kind = .Baiter_Spawn
	case .Bomber:
		g.entities[idx] = make_bomber(&g.assets, ps.pos)
		spawn_kind = .Bomber_Spawn
	case .Human:
		g.entities[idx] = make_human(&g.assets, ps.pos)
		spawn_kind = .Human_Spawn
	}
	push_event(&g.events, {kind = spawn_kind, pos = ps.pos, entity_idx = idx})
}
