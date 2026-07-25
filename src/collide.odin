package main

import rl "vendor:raylib"

// Axis-aligned box collision, world-wraparound aware. Boxes are world-space
// [x1,y1,x2,y2]. Sprites are top-left anchored (drawn at pos), so an
// entity's box is [pos.x, pos.y, pos.x+w, pos.y+h].
Box :: struct {
	x1, y1, x2, y2: f32,
}

entity_box :: proc(pos: rl.Vector2, w, h: f32) -> Box {
	return Box{pos.x, pos.y, pos.x + w, pos.y + h}
}

// A laser is a horizontal beam from pos.x extending `len`, which may be
// negative when firing left.
laser_box :: proc(pos: rl.Vector2, len: f32) -> Box {
	x1 := pos.x
	x2 := pos.x + len
	if x2 < x1 {
		x1, x2 = x2, x1
	}
	return Box{x1, pos.y - 4, x2, pos.y + 4}
}

// Do two boxes overlap, allowing the world to wrap horizontally at
// world_width?
overlap :: proc(a, b: Box, world_width: f32) -> bool {
	// vertical ranges must overlap
	if !(a.y1 < b.y2 && b.y1 < a.y2) {
		return false
	}
	// horizontal ranges, trying b shifted by -world, 0, +world for wraparound
	for off in ([3]f32{-world_width, 0, world_width}) {
		if a.x1 < b.x2+off && b.x1+off < a.x2 {
			return true
		}
	}
	return false
}
