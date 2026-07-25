package main

import "core:math/rand"

// rand_int returns a random integer in [lo, hi] inclusive.
rand_int :: proc(lo, hi: int) -> int {
	if hi <= lo {
		return lo
	}
	return lo + rand.int_max(hi - lo + 1)
}

// rand_f32 returns a random float in [lo, hi).
rand_f32 :: proc(lo, hi: f32) -> f32 {
	return lo + rand.float32() * (hi - lo)
}

clamp_int :: proc(v, lo, hi: int) -> int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// shortest_dx is the signed shortest distance from `from` to `to` around a
// world that wraps at world_width.
shortest_dx :: proc(from, to, world_width: f32) -> f32 {
	dx := to - from
	if dx > world_width/2 {
		dx -= world_width
	}
	if dx < -world_width/2 {
		dx += world_width
	}
	return dx
}
