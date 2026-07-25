package main

import rl "vendor:raylib"

// Procedural terrain: one height sample per world-x unit, generated once at
// startup via a random walk and never reallocated (fixed-size array sized to
// the whole world width -- see WORLD_WIDTH in config.odin).
Mountains :: struct {
	max_height: f32,
	points:     [WORLD_WIDTH]f32,
	exploding:  bool,
	hidden:     bool, // set/cleared by level_finish/level_start, see apply_mountain_events()
}

make_mountains :: proc(max_height: f32) -> Mountains {
	m: Mountains
	m.max_height = max_height
	mountains_generate_points(&m)
	return m
}

mountains_generate_points :: proc(m: ^Mountains) {
	h := f32(0)
	dh := f32(1)
	for i in 0 ..< WORLD_WIDTH {
		m.points[i] = h
		h += dh
		if h <= 0 || h >= m.max_height {
			dh = -dh
			h += dh
		}
		if rand_int(0, 100) == 0 {
			dh = -dh
		}
	}

	// Backfill the right side so the terrain reaches 0 height by both ends
	// of the world.
	h = 0
	dh = 1
	i := WORLD_WIDTH - 1
	for i > 0 {
		i -= 1
		if h >= m.points[i] {
			break
		}
		m.points[i] = h
		h += dh
	}
}

mountains_explode :: proc(m: ^Mountains) {
	m.exploding = true
}

// Hidden for the duration of the level-complete banner. `from` lets
// game.odin re-run this over just the tail of events tick_game_controller
// pushes -- Level_Start/Level_Finish are only ever pushed from inside its
// own state transitions, which run after this consumer's normal per-frame
// pass, so those two need a second look the same frame they're pushed.
apply_mountain_events :: proc(g: ^Game, from := 0) {
	for i in from ..< g.events.count {
		#partial switch g.events.events[i].kind {
		case .Level_Finish:
			g.mountains.hidden = true
		case .Level_Start:
			g.mountains.hidden = false
		}
	}
}

mountains_update :: proc(m: ^Mountains) {
	if !m.exploding {
		return
	}
	for _ in 0 ..< MOUNTAIN_EXPLODE_POINTS_PER_FRAME {
		idx := rand_int(0, WORLD_WIDTH - 1)
		m.points[idx] += f32(rand_int(-MOUNTAIN_JITTER_MAX, MOUNTAIN_JITTER_MAX))
		if rand_int(0, MOUNTAIN_COLLAPSE_CHANCE) == 0 {
			m.points[idx] = MOUNTAIN_COLLAPSE_HEIGHT
		}
	}
}

// get returns the terrain height at world-x wx (properly wrapped -- wx can be
// negative when the camera sits near world-x 0, unlike a plain "%").
mountains_get :: proc(m: ^Mountains, wx: f32) -> f32 {
	idx := int(wx) %% WORLD_WIDTH
	return m.points[idx]
}

mountains_draw :: proc(m: ^Mountains, cam: ^Camera) {
	if m.hidden {
		return
	}
	r := f32(2)
	if m.exploding {
		r = 4 // chunkier debris once the terrain starts crumbling
	}
	for x in 0 ..< WIDTH {
		if x % 5 == 0 {
			h := mountains_get(m, f32(x) + cam.x)
			rl.DrawCircle(i32(x), i32(f32(HEIGHT) - h), r, TERRAIN_ORANGE)
		}
	}
}
