package main

import rl "vendor:raylib"

// Minimap strip along the top of the screen. All geometry is derived from
// compile-time constants.
RADAR_WIDTH :: WIDTH / 2
RADAR_POS :: WIDTH / 2 - RADAR_WIDTH / 2
RADAR_END :: RADAR_POS + RADAR_WIDTH
RADAR_HEIGHT :: 100
RADAR_WXSCALE :: f32(RADAR_WIDTH) / f32(WORLD_WIDTH)
RADAR_WYSCALE :: f32(RADAR_HEIGHT) / f32(HEIGHT)

draw_radar :: proc(g: ^Game, cam: ^Camera) {
	rl.DrawLine(RADAR_POS, 0, RADAR_POS, RADAR_HEIGHT, COLOUR_RED)
	rl.DrawLine(RADAR_END, 0, RADAR_END, RADAR_HEIGHT, COLOUR_RED)
	rl.DrawLine(0, RADAR_HEIGHT, WIDTH, RADAR_HEIGHT, COLOUR_RED)
	half_width := f32(WIDTH) / 2 // runtime value: the constant expression below isn't an exact integer
	cross1 := i32(half_width - f32(RADAR_WIDTH)*RADAR_WXSCALE)
	cross2 := i32(half_width + f32(RADAR_WIDTH)*RADAR_WXSCALE)
	rl.DrawLine(cross1, 0, cross1, RADAR_HEIGHT, COLOUR_WHITE)
	rl.DrawLine(cross2, 0, cross2, RADAR_HEIGHT, COLOUR_WHITE)

	// terrain silhouette
	ww2 := f32(WORLD_WIDTH) / 2
	sw2 := f32(WIDTH) / 2
	c := f32(0)
	for c < WORLD_WIDTH {
		idx := c + ww2 + cam.x + sw2
		mh := mountains_get(&g.mountains, idx)
		rh := mh * RADAR_WYSCALE
		ry := f32(RADAR_HEIGHT) - 2 - rh
		rx := f32(RADAR_POS) + c*RADAR_WXSCALE
		rl.DrawPixel(i32(rx), i32(ry), TERRAIN_ORANGE)
		c += 30
	}

	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active || !e.radar_visible {
			continue
		}
		rx, ry := radar_entity_pos(cam, e.pos, sw2)
		if e.kind == .Lander {
			// two-tone dot: yellow upper half, green lower half
			rl.DrawRectangle(i32(rx), i32(ry), 5, 2, COLOUR_YELLOW)
			rl.DrawRectangle(i32(rx), i32(ry)+2, 5, 3, COLOUR_GREEN)
		} else {
			rl.DrawRectangle(i32(rx), i32(ry), 5, 5, e.radar_colour)
		}
	}

	// player: a distinct white blob (not part of the entity pool)
	prx, pry := radar_entity_pos(cam, g.player.pos, sw2)
	rl.DrawCircle(i32(prx)+2, i32(pry)+2, 3, COLOUR_WHITE)
}

radar_entity_pos :: proc(cam: ^Camera, pos: rl.Vector2, sw2: f32) -> (f32, f32) {
	screenx := pos.x - cam.x - sw2
	scx := screenx * RADAR_WXSCALE
	rx := sw2 + scx
	if rx > RADAR_END {
		rx -= RADAR_WIDTH
	}
	if rx < RADAR_POS {
		rx += RADAR_WIDTH
	}
	ry := pos.y * RADAR_WYSCALE
	return rx, ry
}
