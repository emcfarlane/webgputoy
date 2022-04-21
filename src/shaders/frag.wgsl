struct Uniforms {
    iResolution: vec3<f32>,
    iTime: f32,
    iMouse: vec4<f32>,
    _tiles_per_side: u32,
    _tile_num: u32,
}

struct VertexOutput {
    @location(0) v_tex_coords: vec2<f32>,
    @builtin(position) member: vec4<f32>,
}

struct FragmentOutput {
    @location(0) fragColor: vec4<f32>,
}

@group(0) @binding(0) 
var<uniform> global: Uniforms;
var<private> fragColor_1: vec4<f32>;
var<private> gl_FragCoord: vec4<f32>;

fn main_1() {
    var o: vec4<f32>;

    let _e14 = gl_FragCoord;
    let _e16 = gl_FragCoord;
    mainImage((&o), _e16.xy);
    let _e18 = o;
    fragColor_1 = _e18;
    return;
}

@stage(fragment)
fn main(@builtin(position) param: vec4<f32>) -> FragmentOutput {
    gl_FragCoord = param;
    main_1();
    let _e15 = fragColor_1;
    return FragmentOutput(_e15);
}
