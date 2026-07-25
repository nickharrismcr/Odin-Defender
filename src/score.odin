package main

import rl "vendor:raylib"

// Score counter, event-driven via the event queue (see event.odin). A
// mutated lander is still the same underlying entity, just renamed on
// mutation, so it keeps a lander's value. human_caught/human_saved are the
// rescue bonuses, also shown as a floating popup by bonus.odin.
Score :: struct {
	value: int,
	x, y:  f32,
	cycle: Colour_Cycle,
}

SCORE_PALETTE := [4]rl.Color{COLOUR_RED, COLOUR_BLUE, COLOUR_PURPLE, COLOUR_YELLOW}

init_score :: proc(x, y: f32) -> Score {
	s: Score
	s.x = x
	s.y = y
	s.cycle = make_colour_cycle(SCORE_PALETTE, 45)
	return s
}

score_points_for :: proc(kind: Event_Kind) -> (int, bool) {
	#partial switch kind {
	case .Lander_Killed, .Mutant_Killed, .Swarmer_Killed:
		return 150, true
	case .Baiter_Killed:
		return 200, true
	case .Bomber_Killed:
		return 250, true
	case .Pod_Killed:
		return 1000, true
	case .Human_Caught:
		return 500, true
	case .Human_Saved:
		return 250, true
	}
	return 0, false
}

// Scans this frame's event queue for anything worth points -- a new NPC
// only needs an entry in score_points_for() to start scoring.
apply_score_events :: proc(g: ^Game) {
	for i in 0 ..< g.events.count {
		points, ok := score_points_for(g.events.events[i].kind)
		if ok {
			g.score.value += points
		}
	}
}

update_score :: proc(s: ^Score) {
	colour_cycle_update(&s.cycle)
}

draw_score :: proc(s: ^Score, font: ^Font) {
	font_draw(font, zero_pad(s.value, 7), s.x, s.y, colour_cycle_get(&s.cycle))
}
