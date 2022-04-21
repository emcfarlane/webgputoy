struct fpPreviewUniforms {
    iResolution: vec3<f32>,
    iTime: f32,
    iMouse: vec4<f32>,
    _tiles_per_side: u32,
    _tile_num: u32,
}

struct Uniforms {
    iResolution: vec3<f32>,
    iTime: f32,
    iMouse: vec4<f32>,
    _tiles_per_side: u32,
    _tile_num: u32,
}

struct VertexOutput {
    @builtin(position) member: vec4<f32>,
}

@group(0) @binding(0) 
var<uniform> global: Uniforms;
var<private> gl_VertexIndex: u32;
var<private> gl_Position: vec4<f32>;

fn main_1() {
    var pos: vec2<f32>;
    var dx: u32;
    var dy: u32;

    let _e12 = gl_VertexIndex;
    switch _e12 {
        case 0u: {
            pos = vec2<f32>(0.0, 1.0);
        }
        case 1u: {
            pos = vec2<f32>(0.0, 0.0);
        }
        case 2u: {
            pos = vec2<f32>(1.0, 0.0);
        }
        case 3u: {
            pos = vec2<f32>(0.0, 1.0);
        }
        case 4u: {
            pos = vec2<f32>(1.0, 0.0);
        }
        case 5u: {
            pos = vec2<f32>(1.0, 1.0);
        }
        default: {
            pos = vec2<f32>(f32(0));
        }
    }
    let _e40 = global._tile_num;
    let _e41 = global._tiles_per_side;
    dx = (_e40 % _e41);
    let _e44 = global._tile_num;
    let _e45 = global._tiles_per_side;
    dy = (_e44 / _e45);
    let _e55 = dx;
    let _e56 = dy;
    let _e62 = global._tiles_per_side;
    let _e67 = pos;
    let _e71 = global._tiles_per_side;
    pos = ((vec2<f32>(f32(-(1)), f32(-(1))) + ((vec2<f32>(f32(_e55), f32(_e56)) * 2.0) / vec2<f32>(f32(_e62)))) + ((_e67 * f32(2)) / vec2<f32>(f32(_e71))));
    let _e77 = pos;
    gl_Position = vec4<f32>(_e77.x, _e77.y, 0.0, 1.0);
    return;
}

@stage(vertex)
fn main(@builtin(vertex_index) param: u32) -> VertexOutput {
    gl_VertexIndex = param;
    main_1();
    let _e13 = gl_Position;
    return VertexOutput(_e13);
}
