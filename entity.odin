package main

import rl "vendor:raylib"

Entity_Kind :: enum {
	None,
	Lander,
	Mutant,
	Pod,
	Swarmer,
	Baiter,
	Bomber,
	Human,
}

Lander_State :: enum {
	Materialize,
	Descend,
	Search,
	Grab,
	Abduct,
	Mutated,
	Die,
}

Human_State :: enum {
	Walking,
	Grabbed,
	Dropping,
	Caught,
	Dying,
	Eaten,
}

Carrier_Kind :: enum {
	None,
	Lander,
	Player,
}

// One "fat" struct covering every enemy/human kind, stored in a single
// fixed-capacity pool (Game.entities). Mirrors the original's single flat
// entities list far better than per-kind pools would, and makes the
// lander-to-mutant in-place mutation trivial. State machines are preserved
// as update_func/draw_func proc-pointer fields, matching every stateful
// object's enter_<state>/state_<state> convention in the original (see
// npc.lox, lander.lox, human.lox, player.lox).
Entity :: struct {
	active:              bool, // pool occupancy; released the instant the original would set alive=false
	visible:             bool,
	kind:                Entity_Kind,
	dying:               bool,
	shootable, deadly, chosen: bool,

	pos, dp: rl.Vector2,
	sheet:   Sprite_Sheet,

	disperse, disperse_rate, disperse_max: f32,

	radar_visible: bool,
	radar_colour:  rl.Color,

	counter:     int,
	wait_frames: int, // baiter: Wait-state countdown
	nextthink:   int, // swarmer/baiter: re-aim countdown
	maxspeed:    f32, // swarmer/baiter chase speed
	x_to_player: f32, // baiter: x-offset re-anchored during materialize

	update_func: proc(^Entity, ^Game),
	draw_func:   proc(^Entity, ^Game, ^Camera),

	lander_state: Lander_State, // lander/mutant only
	human_idx:    int,          // lander only: pool index of chosen/grabbed human, -1 = none

	human_state:  Human_State, // human only
	drop_start_y: f32,         // human only
	carrier_kind: Carrier_Kind, // human only
	carrier_idx:  int,         // human only: valid iff carrier_kind == .Lander
}

// acquire_entity returns the index of a free pool slot, or -1 if the pool is
// exhausted (matches the original's pools, which just silently don't
// fire/spawn when full -- see the porting plan's pool-sizing notes).
acquire_entity :: proc(g: ^Game) -> int {
	for i in 0 ..< MAX_ENTITIES {
		if !g.entities[i].active {
			return i
		}
	}
	return -1
}

// update_entities advances every active entity's state machine, then applies
// horizontal world wraparound. Ported from NPC.update()/Lander.update()'s
// shared shape (counter++, dispatch, wrap).
//
// The original's Lander instead snaps position to exactly 0/worldwidth on
// wrap (losing the overflow remainder), while every other kind preserves it
// -- almost certainly an unintentional inconsistency, since at these speeds
// the difference is a couple of pixels at most. Unified here to the
// remainder-preserving version for every kind.
update_entities :: proc(g: ^Game) {
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active {
			continue
		}
		e.counter += 1
		if e.update_func != nil {
			e.update_func(e, g)
		}
		if e.pos.x > WORLD_WIDTH {
			e.pos.x -= WORLD_WIDTH
		}
		if e.pos.x < 0 {
			e.pos.x += WORLD_WIDTH
		}
	}
}

// enemies_hidden hides everything except humans (matches EntityMgr.draw()) --
// set/cleared directly by the player's own state functions while safe-
// starting/exploding, see player.odin.
draw_entities :: proc(g: ^Game, cam: ^Camera) {
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active || !e.visible {
			continue
		}
		if g.mgr.enemies_hidden && e.kind != .Human {
			continue
		}
		if e.draw_func != nil {
			e.draw_func(e, g, cam)
		}
	}
}

// Is e currently mid disperse-death animation? Death tracking differs by
// kind (Lander/Mutant use lander_state, Human uses human_state, the
// simpler NPC kinds share the generic `dying` flag) -- see
// deactivate_dying_entities for why this needs checking uniformly.
entity_is_dying :: proc(e: ^Entity) -> bool {
	switch e.kind {
	case .Lander, .Mutant:
		return e.lander_state == .Die
	case .Human:
		return e.human_state == .Dying
	case .Pod, .Swarmer, .Baiter, .Bomber:
		return e.dying
	case .None:
	}
	return false
}

// Force-deactivates every entity currently mid disperse-death animation.
// Called when the player dies: freeze_enemies() pauses every entity's
// update (including the death-animation countdown itself), so without this
// anything already dying for an unrelated reason (an earlier laser hit, a
// smart bomb) would sit visibly frozen mid-shatter for the whole death/
// respawn sequence instead of just disappearing. check_collisions already
// handles the single entity that caused THIS particular death (see its
// "was_dying" check); this covers every other one.
deactivate_dying_entities :: proc(g: ^Game) {
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if e.active && entity_is_dying(e) {
			e.active = false
		}
	}
}

// Shared death sequence for the simpler NPC kinds (pod/swarmer/baiter/
// bomber) -- ported from npc.lox's enter_die/state_die. Lander and Human
// have their own die logic instead (see npc_lander.odin/npc_human.odin),
// since both need extra teardown (dropping/releasing a carried human) that
// doesn't fit this shared version.
entity_enter_die :: proc(e: ^Entity, g: ^Game) {
	if e.dying {
		return
	}
	e.dying = true
	e.draw_func = entity_draw_dispersed
	e.update_func = entity_state_die
	e.disperse = 1
	e.dp = {0, 0}
	e.shootable = false
	e.deadly = false
	e.radar_visible = false
	entity_on_die(e, g)
	kill_kind: Event_Kind
	switch e.kind {
	case .Pod:
		kill_kind = .Pod_Killed
	case .Swarmer:
		kill_kind = .Swarmer_Killed
	case .Baiter:
		kill_kind = .Baiter_Killed
	case .Bomber:
		kill_kind = .Bomber_Killed
	case .None, .Lander, .Mutant, .Human:
	// unreachable: entity_enter_die is only ever called for the four kinds above
	}
	push_event(&g.events, {kind = kill_kind, pos = e.pos, entity_idx = entity_index(g, e)})
}

entity_state_die :: proc(e: ^Entity, g: ^Game) {
	e.disperse += e.disperse_rate
	if e.disperse >= e.disperse_max {
		e.active = false
	}
}

// Death side-effect hook (only Pod overrides this, in the original, to
// release its swarmers) -- dispatched by kind since Odin has no virtual
// methods.
entity_on_die :: proc(e: ^Entity, g: ^Game) {
	if e.kind == .Pod {
		add_swarmers(g, g.mgr.swarmers_per_pod, e.pos.x, e.pos.y)
	}
}

// entity_hit dispatches a laser/smart-bomb hit to the right kind-specific
// handler -- each kind's own hit()/enter_die() in the original.
entity_hit :: proc(e: ^Entity, g: ^Game) {
	switch e.kind {
	case .Lander, .Mutant:
		lander_hit(e, g)
	case .Human:
		human_hit(e, g)
	case .Pod, .Swarmer, .Baiter, .Bomber:
		entity_enter_die(e, g)
	case .None:
	}
}

// entity_index recovers the pool index of an ^Entity known to point into
// g.entities (every ^Entity in play does, since the pool never reallocates)
// -- needed where a proc only has the entity pointer but must pass "which
// slot is this" on to something else (e.g. becoming another entity's
// carrier).
entity_index :: proc(g: ^Game, e: ^Entity) -> int {
	base := &g.entities[0]
	return int((uintptr(e) - uintptr(base)) / size_of(Entity))
}

// Maximum world-distance (wrapped) a lander will consider when picking a
// human target -- shrinks each wave down to a floor, so landers get more
// selective/local as the game progresses rather than always being willing
// to trek across the whole world for any unclaimed human.
human_search_radius :: proc(level: int) -> f32 {
	r := f32(SEARCH_RADIUS_BASE) - f32(level-1)*f32(SEARCH_RADIUS_STEP)
	return max(r, f32(SEARCH_RADIUS_MIN))
}

// Finds the nearest unclaimed human to from_x, within this wave's search
// radius, claiming it, or -1 if none qualifies. The original just returned
// the first unclaimed human in pool order (i.e. effectively arbitrary
// relative to the lander) -- picking the nearest one within a wave-scaled
// radius is a deliberate enhancement over that, at the user's request.
// Ported (structurally) from EntityMgr.pick_a_human().
pick_a_human :: proc(g: ^Game, from_x: f32) -> int {
	radius := human_search_radius(g.controller.level)
	best := -1
	best_d := f32(0)
	for i in 0 ..< MAX_ENTITIES {
		e := &g.entities[i]
		if !e.active || e.kind != .Human || e.chosen {
			continue
		}
		d := abs(shortest_dx(from_x, e.pos.x, WORLD_WIDTH))
		if d > radius {
			continue
		}
		if best == -1 || d < best_d {
			best = i
			best_d = d
		}
	}
	if best != -1 {
		g.entities[best].chosen = true
	}
	return best
}
