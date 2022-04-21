const std = @import("std");
const utils = @import("utils.zig");
const c = @import("c.zig").c;
const glfw = @import("glfw");

const vertWGSL = @embedFile("shaders/vert.wgsl");
const fragWGSL = @embedFile("shaders/frag.wgsl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const setup = try utils.setup(allocator);
    const queue = c.wgpuDeviceGetQueue(setup.device);
    const framebuffer_size = try setup.window.getFramebufferSize();
    const start_time = std.time.milliTimestamp();

    // READ FILE
    var arg_it = std.process.args();
    _ = arg_it.skip();
    const shader_path = arg_it.next() orelse "examples/colours.wgsl";
    std.debug.print("Loading: {s}.\n", .{shader_path});
    const shader_src = try utils.read_file(allocator, shader_path);

    const full_src = try allocator.alloc(u8, fragWGSL.len + shader_src.len + 1); // null terminate
    std.mem.copy(u8, full_src, fragWGSL);
    std.mem.copy(u8, full_src[fragWGSL.len..], shader_src);
    defer allocator.free(full_src);
    //

    const window_data = try allocator.create(WindowData);
    window_data.* = .{
        .surface = null,
        .swap_chain = null,
        .swap_chain_format = undefined,
        .current_desc = undefined,
        .target_desc = undefined,
    };
    setup.window.setUserPointer(window_data);

    // If targetting OpenGL, we can't use the newer WGPUSurface API. Instead, we need to use the
    // older Dawn-specific API. https://bugs.chromium.org/p/dawn/issues/detail?id=269&q=surface&can=2
    const use_legacy_api = setup.backend_type == c.WGPUBackendType_OpenGL or setup.backend_type == c.WGPUBackendType_OpenGLES;
    var descriptor: c.WGPUSwapChainDescriptor = undefined;
    if (!use_legacy_api) {
        std.debug.print("using legacy OpenGL API\n", .{});
        window_data.swap_chain_format = c.WGPUTextureFormat_BGRA8Unorm;
        descriptor = c.WGPUSwapChainDescriptor{
            .nextInChain = null,
            .label = "basic swap chain",
            .usage = c.WGPUTextureUsage_RenderAttachment,
            .format = window_data.swap_chain_format,
            .width = framebuffer_size.width,
            .height = framebuffer_size.height,
            .presentMode = c.WGPUPresentMode_Fifo,
            .implementation = 0,
        };
        window_data.surface = utils.createSurfaceForWindow(
            setup.instance,
            setup.window,
            comptime utils.detectGLFWOptions(),
        );
    } else {
        const binding = c.machUtilsCreateBinding(setup.backend_type, @ptrCast(*c.GLFWwindow, setup.window.handle), setup.device);
        if (binding == null) {
            @panic("failed to create Dawn backend binding");
        }
        descriptor = std.mem.zeroes(c.WGPUSwapChainDescriptor);
        descriptor.implementation = c.machUtilsBackendBinding_getSwapChainImplementation(binding);
        window_data.swap_chain = c.wgpuDeviceCreateSwapChain(setup.device, null, &descriptor);

        window_data.swap_chain_format = c.machUtilsBackendBinding_getPreferredSwapChainTextureFormat(binding);
        c.wgpuSwapChainConfigure(
            window_data.swap_chain.?,
            window_data.swap_chain_format,
            c.WGPUTextureUsage_RenderAttachment,
            framebuffer_size.width,
            framebuffer_size.height,
        );
    }
    window_data.current_desc = descriptor;
    window_data.target_desc = descriptor;

    //const vs =
    //    \\ @stage(vertex) fn main(
    //    \\     @builtin(vertex_index) VertexIndex : u32
    //    \\ ) -> @builtin(position) vec4<f32> {
    //    \\     var pos = array<vec2<f32>, 3>(
    //    \\         vec2<f32>( 0.0,  0.5),
    //    \\         vec2<f32>(-0.5, -0.5),
    //    \\         vec2<f32>( 0.5, -0.5)
    //    \\     );
    //    \\     return vec4<f32>(pos[VertexIndex], 0.0, 1.0);
    //    \\ }
    //;
    const vs = vertWGSL;
    var vs_wgsl_descriptor = try allocator.create(c.WGPUShaderModuleWGSLDescriptor);
    vs_wgsl_descriptor.chain.next = null;
    vs_wgsl_descriptor.chain.sType = c.WGPUSType_ShaderModuleWGSLDescriptor;
    vs_wgsl_descriptor.source = vs;
    const vs_shader_descriptor = c.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(*const c.WGPUChainedStruct, vs_wgsl_descriptor),
        .label = "my vertex shader",
    };
    const vs_module = c.wgpuDeviceCreateShaderModule(setup.device, &vs_shader_descriptor);

    //const fs =
    //    \\ @stage(fragment) fn main() -> @location(0) vec4<f32> {
    //    \\     return vec4<f32>(1.0, 0.0, 0.0, 1.0);
    //    \\ }
    //;
    std.debug.print("WAHT {s} {}\n", .{ full_src, full_src.len });
    full_src[full_src.len - 1] = 0;
    const fs = full_src[0 .. full_src.len - 1 :0]; //fragWGSL;
    var fs_wgsl_descriptor = try allocator.create(c.WGPUShaderModuleWGSLDescriptor);
    fs_wgsl_descriptor.chain.next = null;
    fs_wgsl_descriptor.chain.sType = c.WGPUSType_ShaderModuleWGSLDescriptor;
    fs_wgsl_descriptor.source = fs;
    const fs_shader_descriptor = c.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(*const c.WGPUChainedStruct, fs_wgsl_descriptor),
        .label = "my fragment shader",
    };
    const fs_module = c.wgpuDeviceCreateShaderModule(setup.device, &fs_shader_descriptor);

    // ---

    ////////////////////////////////////////////////////////////////////////////////
    // Uniform buffers
    const uniform_buffer = c.wgpuDeviceCreateBuffer(
        setup.device,
        &(c.WGPUBufferDescriptor){
            .nextInChain = null,
            .label = "Uniforms",
            .size = @sizeOf(c.fpPreviewUniforms),
            .usage = c.WGPUBufferUsage_Uniform | c.WGPUBufferUsage_CopyDst,
            .mappedAtCreation = false,
        },
    );
    defer c.wgpuBufferRelease(uniform_buffer);

    const bind_group_layout_entries = [_]c.WGPUBindGroupLayoutEntry{
        (c.WGPUBindGroupLayoutEntry){
            .nextInChain = null,
            .binding = 0,
            .visibility = c.WGPUShaderStage_Vertex | c.WGPUShaderStage_Fragment,
            .buffer = (c.WGPUBufferBindingLayout){
                .nextInChain = null,
                .type = c.WGPUBufferBindingType_Uniform,
                .hasDynamicOffset = false,
                .minBindingSize = 0,
            },
            .sampler = undefined,
            .texture = undefined,
            .storageTexture = undefined,
        },

        // ??? Sampler
    };
    const bind_group_layout = c.wgpuDeviceCreateBindGroupLayout(
        setup.device,
        &(c.WGPUBindGroupLayoutDescriptor){
            .nextInChain = null,
            .label = "bind group layout",
            .entryCount = bind_group_layout_entries.len,
            .entries = &bind_group_layout_entries,
        },
    );
    defer c.wgpuBindGroupLayoutRelease(bind_group_layout);

    const bind_group_entries = [_]c.WGPUBindGroupEntry{
        (c.WGPUBindGroupEntry){
            .nextInChain = null,
            .binding = 0,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(c.fpPreviewUniforms),
            .sampler = null, // None
            .textureView = null, // None
        },
    };
    const bind_group = c.wgpuDeviceCreateBindGroup(
        setup.device,
        &(c.WGPUBindGroupDescriptor){
            .nextInChain = null,
            .label = "bind group",
            .layout = bind_group_layout,
            .entryCount = bind_group_entries.len,
            .entries = &bind_group_entries,
        },
    );
    defer c.wgpuBindGroupRelease(bind_group);

    const bind_group_layouts = [_]c.WGPUBindGroupLayout{bind_group_layout};

    const pipeline_layout = c.wgpuDeviceCreatePipelineLayout(
        setup.device,
        &(c.WGPUPipelineLayoutDescriptor){
            .nextInChain = null,
            .label = "my pipeline layout",
            .bindGroupLayoutCount = bind_group_layouts.len,
            .bindGroupLayouts = &bind_group_layouts,
        },
    );
    defer c.wgpuPipelineLayoutRelease(pipeline_layout);

    //
    // ---
    //

    // Fragment state
    var blend = std.mem.zeroes(c.WGPUBlendState);
    blend.color.operation = c.WGPUBlendOperation_Add;
    blend.color.srcFactor = c.WGPUBlendFactor_One;
    blend.color.dstFactor = c.WGPUBlendFactor_One;
    blend.alpha.operation = c.WGPUBlendOperation_Add;
    blend.alpha.srcFactor = c.WGPUBlendFactor_One;
    blend.alpha.dstFactor = c.WGPUBlendFactor_One;

    var color_target = std.mem.zeroes(c.WGPUColorTargetState);
    color_target.format = window_data.swap_chain_format;
    color_target.blend = &blend;
    color_target.writeMask = c.WGPUColorWriteMask_All;

    var fragment = std.mem.zeroes(c.WGPUFragmentState);
    fragment.module = fs_module;
    fragment.entryPoint = "main";
    fragment.targetCount = 1;
    fragment.targets = &color_target;

    //var pipeline_descriptor = std.mem.zeroes(c.WGPURenderPipelineDescriptor);
    //pipeline_descriptor.fragment = &fragment;

    //// Other state
    //pipeline_descriptor.layout = null;
    //pipeline_descriptor.depthStencil = null;

    //pipeline_descriptor.vertex.module = vs_module;
    //pipeline_descriptor.vertex.entryPoint = "main";
    //pipeline_descriptor.vertex.bufferCount = 0;
    //pipeline_descriptor.vertex.buffers = null;

    //pipeline_descriptor.multisample.count = 1;
    //pipeline_descriptor.multisample.mask = 0xFFFFFFFF;
    //pipeline_descriptor.multisample.alphaToCoverageEnabled = false;

    //pipeline_descriptor.primitive.frontFace = c.WGPUFrontFace_CCW;
    //pipeline_descriptor.primitive.cullMode = c.WGPUCullMode_None;
    //pipeline_descriptor.primitive.topology = c.WGPUPrimitiveTopology_TriangleList;
    //pipeline_descriptor.primitive.stripIndexFormat = c.WGPUIndexFormat_Undefined;

    const pipeline = c.wgpuDeviceCreateRenderPipeline(
        setup.device,
        //&pipeline_descriptor
        &(c.WGPURenderPipelineDescriptor){
            .nextInChain = null,
            .label = "a render pipeline",
            .layout = pipeline_layout,
            .vertex = (c.WGPUVertexState){
                .nextInChain = null,
                .module = vs_module,
                .entryPoint = "main",
                .constantCount = 0,
                .constants = null,
                .bufferCount = 0,
                .buffers = null,
            },
            .primitive = (c.WGPUPrimitiveState){
                .nextInChain = null,
                .topology = c.WGPUPrimitiveTopology_TriangleList,
                .stripIndexFormat = c.WGPUIndexFormat_Undefined,
                .frontFace = c.WGPUFrontFace_CCW,
                .cullMode = c.WGPUCullMode_None,
            },
            .depthStencil = null,
            .multisample = (c.WGPUMultisampleState){
                .nextInChain = null,
                .count = 1,
                .mask = 0xFFFFFFFF,
                .alphaToCoverageEnabled = false,
            },
            .fragment = &fragment,
        },
    );
    defer c.wgpuRenderPipelineRelease(pipeline);

    c.wgpuShaderModuleRelease(vs_module);
    c.wgpuShaderModuleRelease(fs_module);

    // Reconfigure the swap chain with the new framebuffer width/height, otherwise e.g. the Vulkan
    // device would be lost after a resize.
    setup.window.setFramebufferSizeCallback((struct {
        fn callback(window: glfw.Window, width: u32, height: u32) void {
            const pl = window.getUserPointer(WindowData);
            pl.?.target_desc.width = width;
            pl.?.target_desc.height = height;
        }
    }).callback);

    // ---
    //const tex_size = (c.WGPUExtent3D){
    //    .width = framebuffer_size.width,
    //    .height = framebuffer_size.height,
    //    .depthOrArrayLayers = 1,
    //};
    //const tex = c.wgpuDeviceCreateTexture(
    //    setup.device,
    //    &(c.WGPUTextureDescriptor){
    //        .nextInChain = null,
    //        .label = "preview_tex",
    //        .usage = (c.WGPUTextureUsage_RenderAttachment | c.WGPUTextureUsage_CopySrc),
    //        .dimension = c.WGPUTextureDimension_2D,
    //        .size = tex_size,
    //        .format = c.WGPUTextureFormat_BGRA8Unorm,
    //        .mipLevelCount = 1,
    //        .sampleCount = 1,
    //        .viewFormatCount = 0,
    //        .viewFormats = null,
    //    },
    //);
    //defer c.wgpuTextureRelease(tex);

    //const view = c.wgpuTextureCreateView(
    //    tex,
    //    &(c.WGPUTextureViewDescriptor){
    //        .nextInChain = null,
    //        .label = "preview_tex_view",
    //        .format = c.WGPUTextureFormat_BGRA8Unorm,
    //        .dimension = c.WGPUTextureViewDimension_2D,
    //        .baseMipLevel = 0,
    //        .mipLevelCount = 1,
    //        .baseArrayLayer = 0,
    //        .arrayLayerCount = 1,
    //        .aspect = c.WGPUTextureAspect_All,
    //    },
    //);
    //defer c.wgpuTextureViewRelease(view);

    // ---

    while (!setup.window.shouldClose()) {
        try frame(.{
            .window = setup.window,
            .device = setup.device,
            .pipeline = pipeline,
            .queue = queue,
            .bind_group = bind_group,
            .start_time = start_time,
            .uniform_buffer = uniform_buffer,
        });
        //std.time.sleep(16 * std.time.ns_per_ms);
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}

const WindowData = struct {
    surface: ?c.WGPUSurface,
    swap_chain: ?c.WGPUSwapChain,
    swap_chain_format: c.WGPUTextureFormat,
    current_desc: c.WGPUSwapChainDescriptor,
    target_desc: c.WGPUSwapChainDescriptor,
};

const FrameParams = struct {
    window: glfw.Window,
    device: c.WGPUDevice,
    pipeline: c.WGPURenderPipeline,
    queue: c.WGPUQueue,
    bind_group: c.WGPUBindGroup,
    start_time: i64,
    uniform_buffer: c.WGPUBuffer,
};

fn isDescriptorEqual(a: c.WGPUSwapChainDescriptor, b: c.WGPUSwapChainDescriptor) bool {
    return a.usage == b.usage and a.format == b.format and a.width == b.width and a.height == b.height and a.presentMode == b.presentMode;
}

fn frame(params: FrameParams) !void {
    try glfw.pollEvents();
    const pl = params.window.getUserPointer(WindowData).?;
    if (pl.swap_chain == null or !isDescriptorEqual(pl.current_desc, pl.target_desc)) {
        const use_legacy_api = pl.surface == null;
        if (!use_legacy_api) {
            pl.swap_chain = c.wgpuDeviceCreateSwapChain(params.device, pl.surface.?, &pl.target_desc);
        } else {
            c.wgpuSwapChainConfigure(
                pl.swap_chain.?,
                pl.swap_chain_format,
                c.WGPUTextureUsage_RenderAttachment,
                @intCast(u32, pl.target_desc.width),
                @intCast(u32, pl.target_desc.height),
            );
        }
        pl.current_desc = pl.target_desc;
    }

    const back_buffer_view = c.wgpuSwapChainGetCurrentTextureView(pl.swap_chain.?);
    var render_pass_info = std.mem.zeroes(c.WGPURenderPassDescriptor);
    var color_attachment = std.mem.zeroes(c.WGPURenderPassColorAttachment);
    color_attachment.view = back_buffer_view;
    color_attachment.resolveTarget = null;
    color_attachment.clearValue = c.WGPUColor{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
    color_attachment.loadOp = c.WGPULoadOp_Clear;
    color_attachment.storeOp = c.WGPUStoreOp_Store;
    render_pass_info.colorAttachmentCount = 1;
    render_pass_info.colorAttachments = &color_attachment;
    render_pass_info.depthStencilAttachment = null;

    const encoder = c.wgpuDeviceCreateCommandEncoder(
        params.device,
        &(c.WGPUCommandEncoderDescriptor){ .nextInChain = null, .label = "preview encoder" },
    );
    // Set the time in the uniforms array
    const time_ms = std.time.milliTimestamp() - params.start_time;
    var uniforms = (c.fpPreviewUniforms){
        .iResolution = .{ .x = @intToFloat(f32, pl.target_desc.width), .y = @intToFloat(f32, pl.target_desc.height), .z = 0 },
        .iTime = @intToFloat(f32, time_ms) / 1000.0,
        .iMouse = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
        ._tiles_per_side = 1, // TODO
        ._tile_num = 0, // TODO
    };
    c.wgpuQueueWriteBuffer(
        params.queue,
        params.uniform_buffer,
        0,
        @ptrCast([*c]const u8, &uniforms),
        @sizeOf(c.fpPreviewUniforms),
    );
    const pass = c.wgpuCommandEncoderBeginRenderPass(encoder, &render_pass_info);
    c.wgpuRenderPassEncoderSetPipeline(pass, params.pipeline);
    c.wgpuRenderPassEncoderSetBindGroup(pass, 0, params.bind_group, 0, 0); // BIND GROUP
    c.wgpuRenderPassEncoderDraw(pass, 6, 1, 0, 0);
    c.wgpuRenderPassEncoderEnd(pass);
    c.wgpuRenderPassEncoderRelease(pass);

    const commands = c.wgpuCommandEncoderFinish(encoder, null);
    c.wgpuCommandEncoderRelease(encoder);

    c.wgpuQueueSubmit(params.queue, 1, &commands);
    c.wgpuCommandBufferRelease(commands);
    c.wgpuSwapChainPresent(pl.swap_chain.?);
    c.wgpuTextureViewRelease(back_buffer_view);
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
