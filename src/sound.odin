package main

import rl "vendor:raylib"

// Sound effects and music. Every clip is loaded once at startup (see
// init_sound_mgr) and only ever triggered/stopped during play -- no
// loading/unloading while the game runs.
Sound_Id :: enum {
	Baiter_Die,
	Bomber_Die,
	Bullet,
	Caught_Human,
	Die,
	Dropping,
	Grabbed,
	Human_Die,
	Lander_Die,
	Laser,
	Level_Start,
	Materialize,
	Mutant,
	Place_Human,
	Pod_Die,
	Start,
	Swarmer,
}

SOUND_PATHS := [Sound_Id]cstring {
	.Baiter_Die   = "assets/baiterdie.wav",
	.Bomber_Die   = "assets/bomberdie.wav",
	.Bullet       = "assets/bullet.wav",
	.Caught_Human = "assets/caughthuman.wav",
	.Die          = "assets/die.wav",
	.Dropping     = "assets/dropping.wav",
	.Grabbed      = "assets/grabbed.wav",
	.Human_Die    = "assets/humandie.wav",
	.Lander_Die   = "assets/landerdie.wav",
	.Laser        = "assets/laser.wav",
	.Level_Start  = "assets/levelstart.wav",
	.Materialize  = "assets/materialise.wav",
	.Mutant       = "assets/mutant.wav",
	.Place_Human  = "assets/placehuman.wav",
	.Pod_Die      = "assets/poddie.wav",
	.Start        = "assets/start.wav",
	.Swarmer      = "assets/swarmer.wav",
}

// Exclusive playback channel, mirroring the arcade's limited hardware voices:
// sounds sharing a non-zero group stop each other before playing -- so
// firing the laser can cut off an NPC death sound or the swarmer buzz, and
// vice versa.
SOUND_GROUP := #partial [Sound_Id]int {
	.Laser      = 1,
	.Lander_Die = 1,
	.Bomber_Die = 1,
	.Baiter_Die = 1,
	.Swarmer    = 1,
	.Dropping   = 1,
}

Sound_Mgr :: struct {
	sounds:     [Sound_Id]rl.Sound,
	background: rl.Music, // ambient loop, plays continuously through every game state
	thruster:   rl.Music, // looped while the ship is thrusting
}

init_sound_mgr :: proc() -> Sound_Mgr {
	sm: Sound_Mgr
	if MUTE {
		return sm
	}
	rl.InitAudioDevice()
	for id in Sound_Id {
		sm.sounds[id] = rl.LoadSound(SOUND_PATHS[id])
	}
	sm.background = rl.LoadMusicStream("assets/background.wav")
	sm.background.looping = true
	sm.thruster = rl.LoadMusicStream("assets/thruster.wav")
	sm.thruster.looping = true
	rl.SetMusicVolume(sm.thruster, 0.3)
	rl.PlayMusicStream(sm.background)
	return sm
}

destroy_sound_mgr :: proc(sm: ^Sound_Mgr) {
	if MUTE {
		return
	}
	for id in Sound_Id {
		rl.UnloadSound(sm.sounds[id])
	}
	rl.UnloadMusicStream(sm.background)
	rl.UnloadMusicStream(sm.thruster)
	rl.CloseAudioDevice()
}

// Restart from the top, stopping every other sound in this one's exclusivity
// group first.
sound_play :: proc(sm: ^Sound_Mgr, id: Sound_Id) {
	if MUTE {
		return
	}
	group := SOUND_GROUP[id]
	if group != 0 {
		for other in Sound_Id {
			if other != id && SOUND_GROUP[other] == group {
				rl.StopSound(sm.sounds[other])
			}
		}
	}
	rl.StopSound(sm.sounds[id])
	rl.PlaySound(sm.sounds[id])
}

sound_stop :: proc(sm: ^Sound_Mgr, id: Sound_Id) {
	if MUTE {
		return
	}
	rl.StopSound(sm.sounds[id])
}

stop_thruster :: proc(sm: ^Sound_Mgr) {
	if MUTE {
		return
	}
	if rl.IsMusicStreamPlaying(sm.thruster) {
		rl.StopMusicStream(sm.thruster)
	}
}

// Only (re)starts if not already playing -- used for the continuous "buzz"
// cues (mutant/swarmer engine hum), re-triggered every frame their entity is
// on screen. Each clip is a short one-shot, so this just lets it repeat for
// as long as the entity stays in view.
sound_play_if_not :: proc(sm: ^Sound_Mgr, id: Sound_Id) {
	if MUTE || rl.IsSoundPlaying(sm.sounds[id]) {
		return
	}
	rl.PlaySound(sm.sounds[id])
}

// Background plays through every game state (intro, play, level-finish
// tally, game over); the thruster loop starts/stops on the ship's thrust
// input edge.
update_music :: proc(g: ^Game) {
	if MUTE {
		return
	}
	sm := &g.sound
	rl.UpdateMusicStream(sm.background)

	if g.player.thrusting {
		if !rl.IsMusicStreamPlaying(sm.thruster) {
			rl.PlayMusicStream(sm.thruster)
		}
		rl.UpdateMusicStream(sm.thruster)
	} else if rl.IsMusicStreamPlaying(sm.thruster) {
		rl.StopMusicStream(sm.thruster)
	}
}

sound_for_event :: proc(kind: Event_Kind) -> (Sound_Id, bool) {
	#partial switch kind {
	case .Level_Start:
		return .Level_Start, true
	case .Lander_Spawn, .Pod_Spawn, .Swarmer_Spawn, .Baiter_Spawn, .Bomber_Spawn:
		return .Materialize, true
	case .Laser_Fire:
		return .Laser, true
	case .Bullet_Fire:
		return .Bullet, true
	case .Player_Explode:
		return .Die, true
	case .Lander_Killed, .Mutant_Killed:
		return .Lander_Die, true
	case .Bomber_Killed:
		return .Bomber_Die, true
	case .Baiter_Killed:
		return .Baiter_Die, true
	case .Pod_Killed:
		return .Pod_Die, true
	case .Human_Grabbed:
		return .Grabbed, true
	case .Human_Dropped:
		return .Dropping, true
	case .Human_Killed:
		return .Human_Die, true
	case .Human_Caught:
		return .Caught_Human, true
	case .Human_Saved:
		return .Place_Human, true
	}
	return .Die, false
}

// Scans this frame's event queue for anything with an associated sound cue
// -- mirrors apply_score_events' pattern in score.odin. `from` lets
// game.odin re-run this over just the tail of events tick_game_controller
// pushes -- Level_Start is only ever pushed from inside its own state
// transitions, which run after this consumer's normal per-frame pass, so
// it needs a second look the same frame it's pushed.
apply_sound_events :: proc(g: ^Game, from := 0) {
	for i in from ..< g.events.count {
		ev := &g.events.events[i]
		// NPC bullets (e.g. a bomber's dropped bombs) can be fired off
		// screen -- that's intentional, they linger as hazards -- but they
		// should stay silent until something on screen is actually shooting.
		if ev.kind == .Bullet_Fire {
			if _, on_screen := camera_translate(&g.cam, ev.pos.x); !on_screen {
				continue
			}
		}
		id, ok := sound_for_event(ev.kind)
		if ok {
			sound_play(&g.sound, id)
		}
	}
}
