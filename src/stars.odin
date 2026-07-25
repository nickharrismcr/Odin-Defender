package main

import rl "vendor:raylib"

NUM_STARS :: 30

Star :: struct {
	pos: rl.Vector2,
	col: rl.Color,
}

// Parallax starfield living entirely in screen space (not world space) --
// update() shifts every star by a small per-frame dx and wraps at the
// screen edges.
Starfield :: struct {
	width, height: f32, // screen-space bounds stars spawn/wrap within
	stars:         [NUM_STARS]Star,
}

make_starfield :: proc(width, height: f32) -> Starfield {
	sf: Starfield
	sf.width = width
	sf.height = height
	for i in 0 ..< NUM_STARS {
		x := f32(rand_int(0, int(width)))
		y := f32(rand_int(100, int(height)))
		sf.stars[i] = Star{pos = {x, y}, col = random_rgb()}
	}
	return sf
}

starfield_update :: proc(sf: ^Starfield, dx: f32) {
	if rand_int(0, 10) < 1 {
		which := rand_int(0, NUM_STARS - 1)
		sf.stars[which].pos = {f32(rand_int(0, int(sf.width))), f32(rand_int(100, int(sf.height)))}
	}
	for i in 0 ..< NUM_STARS {
		s := &sf.stars[i]
		s.pos.x += dx
		if s.pos.x > sf.width {
			s.pos.y = f32(rand_int(100, int(sf.height)))
			s.pos.x = 0
		}
		if s.pos.x < 0 {
			s.pos.y = f32(rand_int(100, int(sf.height)))
			s.pos.x = sf.width
		}
	}
}

starfield_draw :: proc(sf: ^Starfield) {
	for star in sf.stars {
		rl.DrawCircle(i32(star.pos.x), i32(star.pos.y), 2, star.col)
	}
}
