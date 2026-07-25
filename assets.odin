package main

import rl "vendor:raylib"

// All game textures, loaded once at startup and freed once at shutdown.
// No texture is ever loaded/unloaded during play.
Assets :: struct {
	ship:      rl.Texture2D,
	thrust:    rl.Texture2D,
	shipw:     rl.Texture2D,
	smartbomb: rl.Texture2D,
	lander:    rl.Texture2D,
	mutant:    rl.Texture2D,
	human:     rl.Texture2D,
	pod:       rl.Texture2D,
	swarmer:   rl.Texture2D,
	baiter:    rl.Texture2D,
	bomber:    rl.Texture2D,
	bullet:    rl.Texture2D,
	pts250:    rl.Texture2D,
	pts500:    rl.Texture2D,
	font:      rl.Texture2D,

	// intro screen -- not part of the original glox port; sourced from the
	// love2d-defender-master reference project (see game_controller.odin)
	williams:     rl.Texture2D,
	presents:     rl.Texture2D,
	title:        rl.Texture2D,
	title_hilite: rl.Texture2D,
}

load_assets :: proc() -> Assets {
	a: Assets
	a.ship = rl.LoadTexture("assets/ship.png")
	a.thrust = rl.LoadTexture("assets/thrust.png")
	a.shipw = rl.LoadTexture("assets/shipw.png")
	a.smartbomb = rl.LoadTexture("assets/smartbomb.png")
	a.lander = rl.LoadTexture("assets/lander.png")
	a.mutant = rl.LoadTexture("assets/mutant.png")
	a.human = rl.LoadTexture("assets/human.png")
	a.pod = rl.LoadTexture("assets/pod.png")
	a.swarmer = rl.LoadTexture("assets/swarmer.png")
	a.baiter = rl.LoadTexture("assets/baiter.png")
	a.bomber = rl.LoadTexture("assets/bomber.png")
	a.bullet = rl.LoadTexture("assets/bullet.png")
	a.pts250 = rl.LoadTexture("assets/250.png")
	a.pts500 = rl.LoadTexture("assets/500.png")
	a.font = rl.LoadTexture("assets/font.png")
	a.williams = rl.LoadTexture("assets/williams.png")
	a.presents = rl.LoadTexture("assets/presents.png")
	a.title = rl.LoadTexture("assets/title.png")
	a.title_hilite = rl.LoadTexture("assets/title_hilite.png")
	return a
}

unload_assets :: proc(a: ^Assets) {
	rl.UnloadTexture(a.ship)
	rl.UnloadTexture(a.thrust)
	rl.UnloadTexture(a.shipw)
	rl.UnloadTexture(a.smartbomb)
	rl.UnloadTexture(a.lander)
	rl.UnloadTexture(a.mutant)
	rl.UnloadTexture(a.human)
	rl.UnloadTexture(a.pod)
	rl.UnloadTexture(a.swarmer)
	rl.UnloadTexture(a.baiter)
	rl.UnloadTexture(a.bomber)
	rl.UnloadTexture(a.bullet)
	rl.UnloadTexture(a.pts250)
	rl.UnloadTexture(a.pts500)
	rl.UnloadTexture(a.font)
	rl.UnloadTexture(a.williams)
	rl.UnloadTexture(a.presents)
	rl.UnloadTexture(a.title)
	rl.UnloadTexture(a.title_hilite)
}
