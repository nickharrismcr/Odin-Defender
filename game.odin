package main

import rl "vendor:raylib"

// Top-level container owning every game system.
Game :: struct {
	assets:    Assets,
	play_area: rl.RenderTexture2D, // fixed logical-resolution offscreen buffer

	input:     Input,
	cam:       Camera,
	mountains: Mountains,
	stars:     Starfield,
	player:    Player,
	mgr:       Entity_Mgr_State,

	entities:    [MAX_ENTITIES]Entity,
	spawn_queue: [MAX_PENDING_SPAWNS]Pending_Spawn,
	bullets:     [MAX_BULLETS]Bullet,
	lasers:      [MAX_LASERS]Laser,
	particles:   Particle_Pool,
	bonuses:     [MAX_BONUSES]Bonus,
	events:      Event_Queue,

	score:      Score,
	font:       Font,
	controller: Game_Controller,
}

// Game is ~1MB (dominated by the particle pool), so it's heap-allocated
// once at startup rather than declared by value -- a stack-local of this
// size risks overflowing the default thread stack. This is a one-time
// setup allocation, same category as loading textures, not a violation of
// the "no allocation during play" requirement.
init_game :: proc() -> ^Game {
	g := new(Game)
	g.assets = load_assets()
	g.play_area = rl.LoadRenderTexture(WIDTH, HEIGHT)

	g.cam = make_camera(WIDTH, WORLD_WIDTH, 0)
	g.mountains = make_mountains(f32(HEIGHT) * 0.3)
	g.stars = make_starfield(WIDTH, f32(HEIGHT) * 0.7)
	g.player = init_player(&g.assets, {WORLD_WIDTH / 2, HEIGHT / 2})
	g.mgr = init_entity_mgr()
	init_bullet_pool(g)
	init_particle_pool(&g.particles)
	g.score = init_score(10, 10) // left of the radar strip
	g.font = make_font(g.assets.font)
	g.controller = init_game_controller(&g.assets)

	return g
}

destroy_game :: proc(g: ^Game) {
	unload_assets(&g.assets)
	rl.UnloadRenderTexture(g.play_area)
	free(g)
}

update_frame :: proc(g: ^Game) {
	poll_input(&g.input)

	// Fresh event queue for this frame -- gameplay_active() below still
	// reflects last frame's tick_game_controller() call at the bottom of
	// this function, so a state change (e.g. intro -> level_start) takes
	// effect starting next frame.
	clear_events(&g.events)

	if gameplay_active(g) {
		player_update(&g.player, g, &g.input)
		camera_move(&g.cam, player_camera_x(&g.player))
		starfield_update(&g.stars, -g.player.vx/5)
		update_particles(g) // keeps animating even while update_entity_mgr is frozen
		update_entity_mgr(g)
		check_collisions(g)
	}
	// Runs unconditionally (not just during gameplay) so the score's colour
	// cycle keeps animating through the level-finish tally screen too.
	update_score(&g.score)

	// Every consumer reacts to this frame's fresh events (pushed by the
	// gameplay block above) before game_controller's own state tick runs --
	// so e.g. state_level's landers-killed check sees an up-to-date count
	// the instant the last lander dies, not a frame late.
	apply_controller_events(g)
	apply_score_events(g)
	apply_bonus_events(g)
	apply_mountain_events(g)

	tick_game_controller(g, &g.input)

	free_all(context.temp_allocator) // reclaim this frame's zero_pad/tprintf scratch text
}

draw_frame :: proc(g: ^Game) {
	// draw the whole game into the fixed-size play_area texture
	rl.BeginTextureMode(g.play_area)
	rl.ClearBackground(COLOUR_BLACK)
	// Intro, Level_Finish, and Game_Over all hide the world itself --
	// stars/terrain/entities/ship disappear. The radar
	// (its border/crosshair lines plus terrain silhouette and any surviving
	// humans) and score stay up during Level_Finish/Game_Over, but neither
	// shows during Intro (nothing meaningful for either to display yet).
	// mountains_draw also no-ops via its own hidden flag (see
	// apply_mountain_events), independently of this check.
	hide_world := g.controller.state == .Intro || g.controller.state == .Level_Finish || g.controller.state == .Game_Over
	if !hide_world {
		mountains_draw(&g.mountains, &g.cam)
		starfield_draw(&g.stars)
		draw_entities(g, &g.cam)
		draw_bullets(g, &g.cam)
		draw_lasers(g, &g.cam)
		draw_particles(g, &g.cam)
		draw_bonuses(g, &g.cam)
		draw_bomb_flash(g)
		player_draw(&g.player, &g.cam)
	}
	if g.controller.state != .Intro {
		draw_radar(g, &g.cam)
		draw_score(&g.score, &g.font)
	}
	draw_game_controller(g)
	rl.EndTextureMode()

	// blit it centered onto the real (possibly fullscreen) window
	rl.BeginDrawing()
	rl.ClearBackground(COLOUR_BLACK)

	offset_x := f32(rl.GetScreenWidth() - WIDTH) / 2
	offset_y := f32(rl.GetScreenHeight() - HEIGHT) / 2

	source := rl.Rectangle{0, 0, f32(g.play_area.texture.width), -f32(g.play_area.texture.height)}
	dest := rl.Rectangle{offset_x, offset_y, f32(WIDTH), f32(HEIGHT)}
	rl.DrawTexturePro(g.play_area.texture, source, dest, {0, 0}, 0, COLOUR_WHITE)

	rl.EndDrawing()
}
