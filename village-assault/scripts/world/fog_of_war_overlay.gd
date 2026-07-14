extends Sprite2D
class_name FogOfWarOverlay

const FOG_SHADER_CODE := """
shader_type canvas_item;

uniform float edge_motion_pixels = 1.4;
uniform float edge_texture_strength = 0.08;
uniform float drift_speed = 0.18;
uniform float world_pixels_per_mask_pixel = 1.0;
uniform float corner_rounding_mask_pixels = 0.75;

float random_value(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 offset = fract(point);
	vec2 blend = offset * offset * (3.0 - 2.0 * offset);
	float top = mix(random_value(cell), random_value(cell + vec2(1.0, 0.0)), blend.x);
	float bottom = mix(
		random_value(cell + vec2(0.0, 1.0)),
		random_value(cell + vec2(1.0, 1.0)),
		blend.x
	);
	return mix(top, bottom, blend.y);
}

float fog_alpha_at(sampler2D fog_texture, vec2 uv) {
	return texture(fog_texture, clamp(uv, vec2(0.0), vec2(1.0))).a;
}

float rounded_fog_alpha(sampler2D fog_texture, vec2 texel_size, vec2 uv) {
	vec2 offset = texel_size * corner_rounding_mask_pixels;
	float center = fog_alpha_at(fog_texture, uv) * 4.0;
	float cardinal = (
		fog_alpha_at(fog_texture, uv + vec2(offset.x, 0.0))
		+ fog_alpha_at(fog_texture, uv - vec2(offset.x, 0.0))
		+ fog_alpha_at(fog_texture, uv + vec2(0.0, offset.y))
		+ fog_alpha_at(fog_texture, uv - vec2(0.0, offset.y))
	) * 2.0;
	float diagonal = (
		fog_alpha_at(fog_texture, uv + offset)
		+ fog_alpha_at(fog_texture, uv - offset)
		+ fog_alpha_at(fog_texture, uv + vec2(offset.x, -offset.y))
		+ fog_alpha_at(fog_texture, uv + vec2(-offset.x, offset.y))
	);
	return (center + cardinal + diagonal) / 16.0;
}

void fragment() {
	vec2 pixel_position = UV / TEXTURE_PIXEL_SIZE * world_pixels_per_mask_pixel;
	float drift = TIME * drift_speed;
	float flow_x = value_noise(pixel_position * 0.035 + vec2(drift, -drift * 0.7));
	float flow_y = value_noise(pixel_position * 0.035 + vec2(19.3 - drift * 0.6, drift));
	vec2 flow = (vec2(flow_x, flow_y) - 0.5) * 2.0;
	vec2 warped_uv = clamp(
		UV + flow * TEXTURE_PIXEL_SIZE * edge_motion_pixels / world_pixels_per_mask_pixel,
		vec2(0.0),
		vec2(1.0)
	);
	float alpha = rounded_fog_alpha(TEXTURE, TEXTURE_PIXEL_SIZE, warped_uv);
	float transition = 4.0 * alpha * (1.0 - alpha);
	float texture_noise = value_noise(pixel_position * 0.075 + vec2(-drift, drift * 0.5));
	alpha = clamp(
		alpha + (texture_noise - 0.5) * edge_texture_strength * transition,
		0.0,
		1.0
	);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
"""

var _shader_material: ShaderMaterial

func _ready() -> void:
	centered = false
	z_as_relative = false
	z_index = 8
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_ensure_shader_material()

func set_fog_texture(mask_texture: Texture2D, world_rect: Rect2, should_show: bool) -> void:
	_ensure_shader_material()
	texture = mask_texture
	position = world_rect.position
	visible = should_show and mask_texture != null
	if mask_texture != null:
		scale = world_rect.size / Vector2(mask_texture.get_size())
		_shader_material.set_shader_parameter(
			"world_pixels_per_mask_pixel",
			maxf(1.0, scale.x)
		)

func _ensure_shader_material() -> void:
	if _shader_material != null:
		return
	var shader := Shader.new()
	shader.code = FOG_SHADER_CODE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	material = _shader_material
