// colors
fn mainImage(fragColor: ptr<function, vec4<f32>>, fragCoord: vec2<f32>) {
	var uv: vec2<f32> = vec2<f32>(
		fragCoord.x/global.iResolution.x,
		fragCoord.y/global.iResolution.y,
	);
	var col: vec3<f32> = 0.5 + 0.5 * cos(global.iTime + uv.x + uv.y + vec3<f32>(f32(0), f32(2), f32(4)));
	(*fragColor) = vec4<f32>(col, f32(1));
}
