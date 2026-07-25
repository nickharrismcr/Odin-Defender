package main

import rl "vendor:raylib"

// The only place raw keys are read; everything else reads the resulting
// flags. Ported from player/controller.lox.
Input :: struct {
	thrust:     bool, // held: accelerate in the facing direction
	reverse:    bool, // edge-triggered: flip facing, zero speed
	up:         bool, // held: move up
	down:       bool, // held: move down
	fire:       bool, // edge-triggered: fire the laser
	smart_bomb: bool, // edge-triggered: kill everything on screen
	hyperspace: bool, // edge-triggered: warp to a random spot
}

poll_input :: proc(in_: ^Input) {
	in_.thrust = rl.IsKeyDown(.RIGHT_SHIFT)
	in_.reverse = rl.IsKeyPressed(.SPACE)
	in_.up = rl.IsKeyDown(.Q)
	in_.down = rl.IsKeyDown(.A)
	in_.fire = rl.IsKeyPressed(.ENTER)
	in_.smart_bomb = rl.IsKeyPressed(.BACKSPACE)
	in_.hyperspace = rl.IsKeyPressed(.LEFT_SHIFT)
}
