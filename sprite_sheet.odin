package main

import rl "vendor:raylib"

// Replaces glox's native `Texture` object (a horizontal filmstrip sprite
// sheet with an animatable playback window). Draw calls advance the current
// frame as a side effect, matching the original.
Sprite_Sheet :: struct {
	texture:         rl.Texture2D,
	frame_width:     f32,
	frame_height:    f32,
	start_frame:     i32, // 1-based inclusive
	end_frame:       i32, // 1-based inclusive
	ticks_per_frame: i32, // 0 = static
	frame:           i32, // 0-based offset within [start_frame, end_frame]
	tick:            i32,
}

make_sprite_sheet :: proc(texture: rl.Texture2D, frames, start_frame, end_frame: i32) -> Sprite_Sheet {
	return Sprite_Sheet{
		texture = texture,
		frame_width = f32(texture.width) / f32(frames),
		frame_height = f32(texture.height),
		start_frame = start_frame,
		end_frame = end_frame,
	}
}

sprite_set_animate :: proc(s: ^Sprite_Sheet, ticks_per_frame: i32) {
	s.ticks_per_frame = ticks_per_frame
}

// Advances the current frame, wrapped within [start_frame,end_frame]. The
// original wraps by the sheet's *total* frame count instead of the playback
// window -- a latent bug when start/end don't span the whole sheet. Fixed
// here deliberately (see the porting plan).
sprite_advance :: proc(s: ^Sprite_Sheet) {
	if s.ticks_per_frame == 0 {
		return
	}
	s.tick += 1
	if s.tick == s.ticks_per_frame {
		s.tick = 0
		window := s.end_frame - s.start_frame + 1
		s.frame = (s.frame + 1) % window
	}
}

sprite_frame_rect :: proc(s: ^Sprite_Sheet) -> rl.Rectangle {
	frame_num := s.start_frame + s.frame // 1-based frame currently on screen
	x := f32(frame_num - 1) * s.frame_width
	return rl.Rectangle{x, 0, s.frame_width, s.frame_height}
}

sprite_draw :: proc(s: ^Sprite_Sheet, pos: rl.Vector2, tint: rl.Color) {
	rl.DrawTextureRec(s.texture, sprite_frame_rect(s), pos, tint)
	sprite_advance(s)
}

// flip mirrors the sprite horizontally (negative source width) -- used for
// facing direction (e.g. the ship art faces right by default).
sprite_draw_flip :: proc(s: ^Sprite_Sheet, x, y: f32, tint: rl.Color, flip: bool) {
	rect := sprite_frame_rect(s)
	if flip {
		rect.width = -rect.width
	}
	rl.DrawTextureRec(s.texture, rect, {x, y}, tint)
	sprite_advance(s)
}

// scale scales the drawn size; (x,y) is the top-left corner of the SCALED
// sprite, not the source frame.
sprite_draw_scaled :: proc(s: ^Sprite_Sheet, x, y: f32, tint: rl.Color, flip: bool, scale: f32) {
	rect := sprite_frame_rect(s)
	if flip {
		rect.width = -rect.width
	}
	abs_width := abs(rect.width)
	dest := rl.Rectangle{x, y, abs_width * scale, rect.height * scale}
	rl.DrawTexturePro(s.texture, rect, dest, {0, 0}, 0, tint)
	sprite_advance(s)
}

// Explicit source rect, e.g. for bitmap font glyph blitting.
sprite_draw_rect :: proc(s: ^Sprite_Sheet, x, y, src_x, src_y, src_w, src_h: f32, tint: rl.Color) {
	rect := rl.Rectangle{src_x, src_y, src_w, src_h}
	rl.DrawTextureRec(s.texture, rect, {x, y}, tint)
	sprite_advance(s)
}

// Draws the sheet's first frame as an 8x8 grid of tiles, each pushed
// radially outward from the sprite's centre scaled by `disperse` (1 =
// assembled, larger = scattered). Used for NPC/player materialise and death
// animations. (sx, sy) is the assembled sprite's top-left on screen.
//
// Deliberately does not advance the sheet's animation: the original calls
// draw_texture_rect once per tile (64x per disperse draw), which mutates the
// sheet's internal frame/tick counters as a side effect that draw_disperse
// itself never reads back (every tile's source rect is always within the
// sheet's first frame, regardless of current frame) -- replicating that
// would only corrupt animation state for the next normal draw once the
// disperse animation ends, with no visible effect during the disperse
// itself, so it's dropped here.
sprite_draw_disperse :: proc(s: ^Sprite_Sheet, sx, sy, disperse: f32, tint: rl.Color) {
	COLS :: 8
	ROWS :: 8
	tw := s.frame_width / COLS
	th := s.frame_height / ROWS
	cx := sx + s.frame_width / 2
	cy := sy + s.frame_height / 2
	for i in 0 ..< COLS {
		for j in 0 ..< ROWS {
			src_x := f32(i) * tw
			src_y := f32(j) * th
			dx := cx + disperse * (src_x - s.frame_width/2)
			dy := cy + disperse * (src_y - s.frame_height/2)
			rect := rl.Rectangle{src_x, src_y, tw, th}
			rl.DrawTextureRec(s.texture, rect, {dx, dy}, tint)
		}
	}
}
