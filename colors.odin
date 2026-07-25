package main

import rl "vendor:raylib"

COLOUR_RED :: rl.Color{255, 0, 0, 255}
COLOUR_GREEN :: rl.Color{0, 255, 0, 255}
COLOUR_BLUE :: rl.Color{0, 0, 255, 255}
COLOUR_YELLOW :: rl.Color{255, 255, 0, 255}
COLOUR_CYAN :: rl.Color{0, 255, 255, 255}
COLOUR_MAGENTA :: rl.Color{255, 0, 255, 255}
COLOUR_BLACK :: rl.Color{0, 0, 0, 255}
COLOUR_WHITE :: rl.Color{255, 255, 255, 255}
COLOUR_GRAY :: rl.Color{130, 130, 130, 255}
COLOUR_PURPLE :: rl.Color{200, 122, 255, 255}

TERRAIN_ORANGE :: rl.Color{255, 150, 0, 255}

// random_rgb returns a random opaque colour (random 0-255 per channel,
// alpha always 255).
random_rgb :: proc() -> rl.Color {
	return rl.Color{u8(rand_int(0, 255)), u8(rand_int(0, 255)), u8(rand_int(0, 255)), 255}
}

// fade_colour dims a colour toward black by `alpha` while keeping it fully
// opaque -- NOT alpha blending, despite the name. The laser's "translucent
// glow" bands are dimmed, opaque rectangles drawn under the brighter core,
// not real transparency.
fade_colour :: proc(c: rl.Color, alpha: f32) -> rl.Color {
	a := clamp(alpha, 0, 1)
	return rl.Color{u8(f32(c.r) * a), u8(f32(c.g) * a), u8(f32(c.b) * a), 255}
}
