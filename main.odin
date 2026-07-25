package main

import rl "vendor:raylib"

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(WIDTH, HEIGHT, "Defender")
	defer rl.CloseWindow()
	rl.SetTargetFPS(TARGET_FPS)

	when FULLSCREEN {
		monitor := rl.GetCurrentMonitor()
		rl.SetWindowSize(rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor))
		rl.ToggleFullscreen()
	}

	g := init_game() // ^Game -- see init_game's doc comment for why it's heap-allocated
	defer destroy_game(g)

	for !rl.WindowShouldClose() && !g.controller.done {
		update_frame(g)
		draw_frame(g)
	}
}
