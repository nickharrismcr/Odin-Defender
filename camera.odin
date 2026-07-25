package main

// 1D horizontal-scrolling camera over a world that wraps at world_width.
// Bespoke game logic (not raylib's Camera2D) -- ported from world/camera.lox.
Camera :: struct {
	screen_width: f32,
	world_width:  f32,
	x:            f32,
}

make_camera :: proc(screen_width, world_width, x: f32) -> Camera {
	return Camera{screen_width = screen_width, world_width = world_width, x = x}
}

camera_move :: proc(cam: ^Camera, x: f32) {
	cam.x = x
}

// Translates a world x to a screen x, or ok=false if off-screen. The world
// wraps at world_width, so a position can be visible via its natural offset
// from the camera, or by wrapping a full world-width forward/back -- try all
// three; screen_width is always far smaller than world_width, so at most one
// wrap can ever land in range.
camera_translate :: proc(cam: ^Camera, wp: f32) -> (f32, bool) {
	p := wp - cam.x
	if p >= 0 && p <= cam.screen_width {
		return p, true
	}
	p2 := p + cam.world_width
	if p2 >= 0 && p2 <= cam.screen_width {
		return p2, true
	}
	p3 := p - cam.world_width
	if p3 >= 0 && p3 <= cam.screen_width {
		return p3, true
	}
	return 0, false
}
