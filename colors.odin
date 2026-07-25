package main

import rl "vendor:raylib"

// Named colours ported from the original glox game's bundled colour.lox
// module. rl.Color is {r,g,b,a: u8}, same 0-255 range as glox's vec4 colours,
// so this is a direct 1:1 mapping.

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

// random_rgb returns a random opaque colour, matching colour_utils.random()
// in the original (random 0-255 per channel, alpha always 255).
random_rgb :: proc() -> rl.Color {
	return rl.Color{u8(rand_int(0, 255)), u8(rand_int(0, 255)), u8(rand_int(0, 255)), 255}
}

// fade_colour matches colour_utils.fade() in the original EXACTLY: despite
// the name, this is NOT alpha blending -- it scales r/g/b down by `alpha`
// and returns a fully OPAQUE colour (alpha always 255). The laser's
// "translucent glow" bands are actually dimmed, opaque rectangles drawn
// under the brighter core, not real alpha transparency. Confirmed by
// reading color_functions.go's ColourUtilsFadeBuiltIn directly.
fade_colour :: proc(c: rl.Color, alpha: f32) -> rl.Color {
	a := clamp(alpha, 0, 1)
	return rl.Color{u8(f32(c.r) * a), u8(f32(c.g) * a), u8(f32(c.b) * a), 255}
}
