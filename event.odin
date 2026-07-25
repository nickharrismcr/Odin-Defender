package main

import rl "vendor:raylib"

// Fixed-size per-frame event queue, replacing the original's closure-based
// pub/sub EventDispatcher (game/event.lox) -- see the porting plan for why
// (Odin procs can't capture enclosing state like glox's closures do).
//
// Lifecycle, all within one update_frame call: cleared at the top, then
// gameplay (entity updates, collisions) pushes this frame's events, then
// every consumer (game_controller's counters, Score, Bonus, Mountains)
// polls the same fully-populated queue, and only THEN does
// tick_game_controller() run its state-machine dispatch -- so e.g.
// state_level's landers-killed check reacts the instant the last lander's
// death event lands, same frame, not a frame late. An earlier version of
// this queue tried to preserve the original's natural cross-frame call-
// order lag by clearing once at the very end of the frame with
// game_controller polling at the top -- that silently dropped every event
// (cleared before game_controller's next poll ever saw them). This
// same-frame design is simpler and was verified against that failure.
Event_Kind :: enum {
	Lander_Spawn,
	Human_Spawn,
	Pod_Spawn,
	Swarmer_Spawn,
	Baiter_Spawn,
	Bomber_Spawn,
	Lander_Searching,
	Human_Grabbed,
	Human_Caught,
	Human_Saved,
	Human_Killed,
	Lander_Mutated,
	Lander_Killed,
	Mutant_Killed,
	Swarmer_Killed,
	Baiter_Killed,
	Bomber_Killed,
	Pod_Killed,
	Bullet_Fire,
	Laser_Fire,
	Player_Hit,
	Player_Die,
	Player_Explode,
	Player_Start,
	Player_Hyperspace,
	Level_Start,
	Level_Finish,
	No_Humans,
}

// One flat "context" struct covers every event kind -- the same fat-struct-
// plus-kind-tag pattern already used for Entity. A trigger site fills in
// whichever fields are relevant to its kind; a consumer reads out only the
// fields it cares about.
Event :: struct {
	kind:       Event_Kind,
	pos:        rl.Vector2, // world position -- spawns, kills, fires
	entity_idx: int,        // pool index of the entity/human involved, -1 if none
	level:      int,        // level number -- Level_Start / Level_Finish only
}

Event_Queue :: struct {
	events: [MAX_EVENTS_PER_FRAME]Event,
	count:  int,
}

push_event :: proc(eq: ^Event_Queue, ev: Event) {
	if eq.count >= MAX_EVENTS_PER_FRAME {
		return // queue full this frame; drop (see the porting plan's pool-sizing notes)
	}
	eq.events[eq.count] = ev
	eq.count += 1
}

clear_events :: proc(eq: ^Event_Queue) {
	eq.count = 0
}
