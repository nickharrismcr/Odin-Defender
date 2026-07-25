package main

import "core:math"
import rl "vendor:raylib"

// Post-processing pass applied to the final blit of the play area onto the
// window: scanlines, CRT barrel distortion, and chromatic separation,
// combined into a single fragment shader. All three operate on the fixed
// logical resolution (WIDTH x HEIGHT), not the physical window size, since
// they're applied while drawing the play_area texture, not the backbuffer
// directly.
PostFX :: struct {
	shader:  rl.Shader,
	enabled: bool,
}

VDU_SHADER_SRC :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform vec2 distortionFactor;
uniform vec2 scaleFactor;
uniform float feather;

uniform vec2 chromaDirection;

uniform float scanWidth;
uniform float scanPhase;
uniform float scanThickness;
uniform float scanOpacity;
uniform vec3 scanColor;
uniform float screenHeight;

vec2 barrel(vec2 uv) {
	uv = uv * 2.0 - vec2(1.0);
	uv *= scaleFactor;
	uv += (uv.yx * uv.yx) * uv * (distortionFactor - 1.0);
	return uv;
}

float edgeMask(vec2 uvPM1) {
	return (1.0 - smoothstep(1.0 - feather, 1.0, abs(uvPM1.x)))
	     * (1.0 - smoothstep(1.0 - feather, 1.0, abs(uvPM1.y)));
}

float sampleScanlined(vec2 srcUV, int channel) {
	vec4 c = texture(texture0, srcUV);
	float v = 0.5 * (sin(srcUV.y * 3.14159 / scanWidth * screenHeight + scanPhase) + 1.0);
	vec3 rgb = c.rgb - (scanColor - c.rgb) * (pow(v, scanThickness) - 1.0) * scanOpacity;
	rgb *= 1.2;
	if (channel == 0) return rgb.r;
	if (channel == 1) return rgb.g;
	return rgb.b;
}

void main() {
	vec2 uv0 = fragTexCoord;

	// chromatic separation is applied post-distortion in the original
	// effect chain, so the shift happens in output space, then each
	// shifted point is distorted independently
	vec2 uvR = barrel(uv0 - chromaDirection);
	vec2 uvG = barrel(uv0);
	vec2 uvB = barrel(uv0 + chromaDirection);

	float mask = edgeMask(uvG);

	vec2 srcR = (uvR + vec2(1.0)) / 2.0;
	vec2 srcG = (uvG + vec2(1.0)) / 2.0;
	vec2 srcB = (uvB + vec2(1.0)) / 2.0;

	float r = sampleScanlined(srcR, 0);
	float g = sampleScanlined(srcG, 1);
	float b = sampleScanlined(srcB, 2);

	finalColor = vec4(r, g, b, 1.0) * mask * fragColor * colDiffuse;
}
`

set_shader_v2 :: proc(shader: rl.Shader, name: cstring, v: [2]f32) {
	v := v
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, name), &v, .VEC2)
}

set_shader_v3 :: proc(shader: rl.Shader, name: cstring, v: [3]f32) {
	v := v
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, name), &v, .VEC3)
}

set_shader_f32 :: proc(shader: rl.Shader, name: cstring, v: f32) {
	v := v
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, name), &v, .FLOAT)
}

init_postfx :: proc() -> PostFX {
	fx: PostFX
	fx.shader = rl.LoadShaderFromMemory(nil, VDU_SHADER_SRC)
	fx.enabled = true

	set_shader_v2(fx.shader, "distortionFactor", {1.03, 1.03})
	set_shader_v2(fx.shader, "scaleFactor", {1, 1})
	set_shader_f32(fx.shader, "feather", 0.02)

	angle := f32(0.5)
	radius := f32(2)
	chroma := [2]f32{math.cos(angle) * radius / f32(WIDTH), math.sin(angle) * radius / f32(HEIGHT)}
	set_shader_v2(fx.shader, "chromaDirection", chroma)

	set_shader_f32(fx.shader, "scanWidth", 2)
	set_shader_f32(fx.shader, "scanPhase", 0)
	set_shader_f32(fx.shader, "scanThickness", 1)
	set_shader_f32(fx.shader, "scanOpacity", 0.7)
	set_shader_v3(fx.shader, "scanColor", {0, 0, 0})
	set_shader_f32(fx.shader, "screenHeight", f32(HEIGHT))

	return fx
}

destroy_postfx :: proc(fx: ^PostFX) {
	rl.UnloadShader(fx.shader)
}

// V toggles the effect off/on, since it's a strong stylistic look some
// players may prefer without.
update_postfx :: proc(fx: ^PostFX) {
	if rl.IsKeyPressed(.V) {
		fx.enabled = !fx.enabled
	}
}
