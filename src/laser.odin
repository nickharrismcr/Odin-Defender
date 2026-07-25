package main

import rl "vendor:raylib"

// The player's laser: a horizontal beam that extends across the screen,
// cycles colour, and expires after a short life. Drawn as filled rectangles
// (a bright core plus a dimmed "glow", see fade_colour's note on why that's
// not real transparency), with small black gaps punched into the glow band,
// randomised every 6 frames, for a crackling look.
Gap :: struct {
	offset, width: f32,
}

Laser :: struct {
	active: bool,
	pos:    rl.Vector2,
	dir:    f32,
	len:    f32,
	speed:  f32,
	age:    int,
	colour: rl.Color,
	gaps:   [LASER_NUM_GAPS]Gap,
}

LASER_COLOURS := [4]rl.Color{COLOUR_YELLOW, COLOUR_CYAN, COLOUR_GREEN, COLOUR_BLUE}

laser_dead :: proc(l: ^Laser) -> bool {
	return !l.active
}

laser_kill :: proc(l: ^Laser) {
	l.active = false
}

laser_reset :: proc(l: ^Laser, x, y, dir, speed: f32, colour: rl.Color) {
	l.active = true
	l.pos = {x, y}
	l.dir = dir
	l.len = 20 * dir
	l.speed = speed + 14 // beam travels faster than the ship
	l.age = 0
	l.colour = colour
	for i in 0 ..< LASER_NUM_GAPS {
		l.gaps[i] = {0, 0} // invisible until the first re-roll
	}
}

// Randomise the black gap segments cut into the glow band: a new
// (offset,width) pair per gap, offset within the beam's current width,
// width in [2,15).
laser_reroll_gaps :: proc(l: ^Laser) {
	w := abs(l.len)
	for i in 0 ..< LASER_NUM_GAPS {
		l.gaps[i] = {rand_f32(0, w), rand_f32(2, 15)}
	}
}

// laser_pool_fire scans for the first dead slot, cycling the round-robin
// colour index on each successful fire. Pool-level primitive -- see
// fire_laser() in entity_mgr.odin for the manager-level wrapper.
laser_pool_fire :: proc(g: ^Game, x, y, dir, speed: f32) {
	for i in 0 ..< MAX_LASERS {
		l := &g.lasers[i]
		if laser_dead(l) {
			g.mgr.laser_colour_idx = (g.mgr.laser_colour_idx + 1) % len(LASER_COLOURS)
			laser_reset(l, x, y, dir, speed, LASER_COLOURS[g.mgr.laser_colour_idx])
			return
		}
	}
}

update_lasers :: proc(g: ^Game) {
	for i in 0 ..< MAX_LASERS {
		l := &g.lasers[i]
		if !l.active {
			continue
		}
		l.pos.x += l.dir * l.speed
		// extend the beam until it spans (up to) the screen width
		if abs(l.len) < WIDTH {
			l.len += l.dir * l.speed * 2
		}
		if l.age % 6 == 0 {
			laser_reroll_gaps(l)
		}
		l.age += 1
		if l.age > 90 {
			l.active = false
		}
	}
}

draw_lasers :: proc(g: ^Game, cam: ^Camera) {
	for i in 0 ..< MAX_LASERS {
		l := &g.lasers[i]
		if !l.active {
			continue
		}
		spos, ok := camera_translate(cam, l.pos.x)
		if !ok {
			continue
		}
		// normalise so width is positive when firing left (negative len)
		x := spos
		w := l.len
		if w < 0 {
			x = spos + w
			w = -w
		}
		ix := i32(x)
		iy := i32(l.pos.y)
		iw := i32(w)
		c := l.colour
		// dimmed "glow" above/below, then the bright core
		rl.DrawRectangle(ix, iy - 4, iw, 8, fade_colour(c, 0.15))
		rl.DrawRectangle(ix, iy - 2, iw, 4, fade_colour(c, 0.3))
		rl.DrawRectangle(ix, iy, iw, 2, c)
		// black gaps cut into the glow band, for the crackling-beam look
		for gap in l.gaps {
			gx := i32(gap.offset)
			gw := i32(gap.width)
			rl.DrawRectangle(ix + gx, iy - 4, gw, 8, COLOUR_BLACK)
		}
	}
}

clear_lasers :: proc(g: ^Game) {
	for i in 0 ..< MAX_LASERS {
		laser_kill(&g.lasers[i])
	}
}
