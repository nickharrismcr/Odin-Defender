package main

import "core:math"
import rl "vendor:raylib"

// One-shot explosion bursts: particles fly outward from the blast point
// starting white-hot, cool through red as they age, then fade out and die.
// This is the only particle effect the game uses, so there's a flat pool
// and a burst-emit that hardcodes the cooling/drag/additive-blend
// behaviour directly, rather than a generic emitter abstraction.
Particle :: struct {
	active:    bool,
	pos, dpos: rl.Vector2,
	age, life: int,
	size:      f32,
	colour:    rl.Color,
}

// Free-index stack for guaranteed O(1) acquire/release -- a single burst can
// churn up to EXPLOSION_PARTICLES (140) slots at once, and a mass-kill
// (smart bomb) can trigger several bursts the same frame, so a linear scan
// like the other (much smaller) pools isn't worth the risk here.
Particle_Pool :: struct {
	slots:      [MAX_PARTICLES]Particle,
	free_stack: [MAX_PARTICLES]int,
	free_count: int,
}

// Takes an out-pointer (into the already heap-allocated Game) rather than
// returning by value -- Particle_Pool is ~900KB, too large to safely pass
// through a stack-returned temporary.
init_particle_pool :: proc(pp: ^Particle_Pool) {
	for i in 0 ..< MAX_PARTICLES {
		pp.free_stack[i] = i
	}
	pp.free_count = MAX_PARTICLES
}

particle_acquire :: proc(pp: ^Particle_Pool) -> int {
	if pp.free_count == 0 {
		return -1
	}
	pp.free_count -= 1
	return pp.free_stack[pp.free_count]
}

particle_release :: proc(pp: ^Particle_Pool, idx: int) {
	pp.slots[idx].active = false
	pp.free_stack[pp.free_count] = idx
	pp.free_count += 1
}

// Queues a one-shot burst of `count` particles at world (x,y).
emit_burst :: proc(g: ^Game, x, y: f32, count: int) {
	for _ in 0 ..< count {
		idx := particle_acquire(&g.particles)
		if idx < 0 {
			return // pool exhausted -- drop the remaining particles
		}
		p := &g.particles.slots[idx]
		angle := rand_f32(0, 2*math.PI)
		speed := rand_f32(1.0, 14.0) // wide spread: some fast, some slow
		p.pos = {x, y}
		p.dpos = {math.cos(angle) * speed, math.sin(angle) * speed}
		p.age = 0
		p.life = rand_int(30, 85)
		p.size = rand_f32(3.0, 7.5) // chunky debris
		p.colour = COLOUR_WHITE // white-hot at birth
		p.active = true
	}
}

update_particles :: proc(g: ^Game) {
	for i in 0 ..< MAX_PARTICLES {
		p := &g.particles.slots[i]
		if !p.active {
			continue
		}
		p.age += 1
		if p.age >= p.life {
			particle_release(&g.particles, i)
			continue
		}
		p.pos += p.dpos

		t := f32(p.age) / f32(p.life) // 0..1 over the particle's life

		// white -> red: pull green and blue down toward zero
		gb := u8(255 * (1.0 - t))

		// hold full brightness, then fade out over the last 40% of life
		a := u8(255)
		if t > 0.6 {
			a = u8(255 * (1.0 - t) / 0.4)
		}
		p.colour = rl.Color{255, gb, gb, a}
		p.dpos *= 0.985 // light drag: particles carry further
	}
}

// Drawn as squares under additive blending -- unlike the laser's
// fade_colour() trick, this genuinely uses alpha blending (real varying
// alpha values combined with rl.BlendAdditive).
draw_particles :: proc(g: ^Game, cam: ^Camera) {
	rl.BeginBlendMode(.ADDITIVE)
	for i in 0 ..< MAX_PARTICLES {
		p := &g.particles.slots[i]
		if !p.active {
			continue
		}
		spos, ok := camera_translate(cam, p.pos.x)
		if !ok {
			continue
		}
		s := i32(p.size * 2) // side length
		rl.DrawRectangle(i32(spos)-s/2, i32(p.pos.y)-s/2, s, s, p.colour)
	}
	rl.EndBlendMode()
}
