package main

import "core:fmt"
import rl "vendor:raylib"

// Bitmap text drawn from the alphanumeric atlas (assets/font.png): a single
// row of 38 glyphs on a 30px pitch, ink 20x30, 25px pen advance. Sliced
// manually (explicit source rects), not through Sprite_Sheet's frame system
// -- there's no "current frame"/animation concept for a font atlas.
Font :: struct {
	tex: rl.Texture2D,
}

make_font :: proc(tex: rl.Texture2D) -> Font {
	return Font{tex = tex}
}

font_char_index :: proc(c: u8) -> int {
	chars := FONT_CHARS
	for i in 0 ..< len(chars) {
		if chars[i] == c {
			return i
		}
	}
	return -1
}

font_width :: proc(s: string) -> f32 {
	return f32(len(s) * FONT_ADVANCE)
}

// Draw s at screen (x,y), tinted col. Characters outside the atlas (a
// space, say) draw nothing but still advance the pen.
font_draw :: proc(font: ^Font, s: string, x, y: f32, col: rl.Color) {
	cx := x
	for i in 0 ..< len(s) {
		idx := font_char_index(s[i])
		if idx >= 0 {
			rect := rl.Rectangle{f32(idx) * FONT_PITCH, 0, FONT_INK_W, FONT_INK_H}
			rl.DrawTextureRec(font.tex, rect, {cx, y}, col)
		}
		cx += FONT_ADVANCE
	}
}

// Left-pad n with zeros to width w. Uses the temp allocator (reset every
// frame) for the transient formatting, so it never grows the heap across
// frames.
zero_pad :: proc(n, w: int) -> string {
	s := fmt.tprintf("%d", n)
	for len(s) < w {
		s = fmt.tprintf("0%s", s)
	}
	return s
}

// Smoothly cycles a colour through a 4-entry palette, taking `steps` frames
// per leg.
Colour_Cycle :: struct {
	palette: [4]rl.Color,
	steps:   int,
	i:       int,
	t:       int,
}

make_colour_cycle :: proc(palette: [4]rl.Color, steps: int) -> Colour_Cycle {
	return Colour_Cycle{palette = palette, steps = steps}
}

colour_cycle_update :: proc(cc: ^Colour_Cycle) {
	cc.t += 1
	if cc.t >= cc.steps {
		cc.t = 0
		cc.i = (cc.i + 1) % len(cc.palette)
	}
}

// Linear blend from the current palette entry toward the next.
colour_cycle_get :: proc(cc: ^Colour_Cycle) -> rl.Color {
	a := cc.palette[cc.i]
	b := cc.palette[(cc.i+1) % len(cc.palette)]
	f := f32(cc.t) / f32(cc.steps)
	return rl.Color{
		u8(f32(a.r) + (f32(b.r) - f32(a.r))*f),
		u8(f32(a.g) + (f32(b.g) - f32(a.g))*f),
		u8(f32(a.b) + (f32(b.b) - f32(a.b))*f),
		255,
	}
}
