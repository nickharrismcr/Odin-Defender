package main

import rl "vendor:raylib"

// Shared per-frame draw helpers used by every NPC-derived kind: a plain
// single-frame draw, and the materialise/death "disperse" shatter draw.
// Ported from npc.lox's draw_normal/draw_dispersed (lander.lox duplicates
// these itself as draw_/draw_exp in the original -- reused here instead,
// since they're functionally identical).
entity_draw_normal :: proc(e: ^Entity, g: ^Game, cam: ^Camera) {
	spos, ok := camera_translate(cam, e.pos.x)
	if !ok {
		return
	}
	sprite_draw(&e.sheet, {spos, e.pos.y}, COLOUR_WHITE)
}

entity_draw_dispersed :: proc(e: ^Entity, g: ^Game, cam: ^Camera) {
	spos, ok := camera_translate(cam, e.pos.x)
	if !ok {
		return
	}
	sprite_draw_disperse(&e.sheet, spos, e.pos.y, e.disperse, COLOUR_WHITE)
}

// Fires a bullet from e that homes in on the player. The invariant is TIME,
// not speed: pick a fixed time-to-target t (frames), then set the shot's
// velocity on each axis independently to whatever distance/t requires, so
// both axes arrive together -- a stationary player is hit dead-on, a moving
// one is led correctly in x. time_mult scales the configured time-to-target
// (>1 gives a slower, more lenient shot). Ported from npc.lox's
// aim_bullet_at().
aim_bullet_at :: proc(g: ^Game, e: ^Entity, time_mult: f32) {
	t := rand_f32(f32(g.mgr.npc_bullet_time)/2, f32(g.mgr.npc_bullet_time)) * time_mult

	tx := g.player.pos.x + g.player.vx*t
	ty := g.player.pos.y

	vx := shortest_dx(e.pos.x, tx, WORLD_WIDTH) / t
	vy := (ty - e.pos.y) / t

	fire_bullet(g, e.pos, {vx, vy})
}

// Per-frame velocity toward where the player will be in `lead` frames,
// clamped to maxspeed. Ported from npc.lox's seek_player().
seek_player :: proc(g: ^Game, e: ^Entity, maxspeed, lead, xoff, yoff: f32) -> rl.Vector2 {
	tx := g.player.pos.x + g.player.vx*lead + xoff
	ty := g.player.pos.y + yoff
	dx := shortest_dx(e.pos.x, tx, WORLD_WIDTH) / lead
	dy := (ty - e.pos.y) / lead
	return rl.Vector2{clamp(dx, -maxspeed, maxspeed), clamp(dy, -maxspeed, maxspeed)}
}
