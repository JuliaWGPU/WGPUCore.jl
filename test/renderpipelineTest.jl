## Load WGPU
using WGPUCore
using Test
using WGPUNative
using GLFW

WGPUCore.setDebugMode(false)
WGPUCore.SetLogLevel(WGPULogLevel_Debug)

shaderSource =
    Vector{UInt8}(
        """
        struct VertexInput {
            @builtin(vertex_index) vertex_index : u32,
        };

        struct VertexOutput {
            @location(0) color : vec4<f32>,
            @builtin(position) pos: vec4<f32>,
        };

        @vertex
        fn vs_main(in: VertexInput) -> VertexOutput {
            var positions = array<vec2<f32>, 3>(vec2<f32>(0.0, -0.5), vec2<f32>(0.5, 0.5), vec2<f32>(-0.5, 0.7));
            let index = i32(in.vertex_index);
            let p: vec2<f32> = positions[index];

            var out: VertexOutput;
            out.pos = vec4<f32>(sin(p), 0.0, 1.0);
            out.color = vec4<f32>(p, 0.5, 1.0);
            return out;
        }

        @fragment
        fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
            return in.color;
        }
        """,
    )
canvas = WGPUCore.defaultCanvas(WGPUCore.WGPUCanvas);
gpuDevice = WGPUCore.getDefaultDevice();
shaderInfo = WGPUCore.loadWGSL(shaderSource);
cshader = WGPUCore.createShaderModule(gpuDevice, "shadercode", shaderInfo.shaderModuleDesc, nothing, nothing);
cshaderRef = cshader |> Ref

bindingLayouts = []
bindings = []

pipelineLayout = WGPUCore.createPipelineLayout(gpuDevice, "PipeLineLayout", bindingLayouts, bindings)
swapChainFormat = WGPUCore.getPreferredFormat(canvas)

renderpipelineOptions = [
    WGPUCore.GPUVertexState => [
        :_module => cshaderRef[],
        :entryPoint => "vs_main",
        :buffers => [
            WGPUCore.GPUVertexBufferLayout => [
                :arrayStride => 6 * 4,
                :stepMode => "Vertex",
                :attributes => [
                    :attribute => [
                        :format => "Float32x4",
                        :offset => 0,
                        :shaderLocation => 0,
                    ],
                    :attribute => [
                        :format => "Float32x2",
                        :offset => 4 * 4,
                        :shaderLocation => 1,
                    ],
                ],
            ],
        ],
    ],
    WGPUCore.GPUPrimitiveState => [
        :topology => "TriangleList",
        :frontFace => "CCW",
        :cullMode => "None",
        :stripIndexFormat => "Undefined",
    ],
    WGPUCore.GPUDepthStencilState => [],
    WGPUCore.GPUMultiSampleState =>
        [:count => 1, :mask => typemax(UInt32), :alphaToCoverageEnabled => false],
    WGPUCore.GPUFragmentState => [
        :_module => cshaderRef[],
        :entryPoint => "fs_main",
        :targets => [
            WGPUCore.GPUColorTargetState => [
                :format => swapChainFormat,
                :color => [:srcFactor => "One", :dstFactor => "Zero", :operation => "Add"],
                :alpha => [:srcFactor => "One", :dstFactor => "Zero", :operation => "Add"],
            ],
        ],
    ],
]

function createRenderPipeline(
    gpuDevice,
    pipelinelayout,
    renderpipeline;
    label = "RenderPipeLine",
)
    renderArgs = Dict()
    for state in renderpipeline
        obj = WGPUCore.createEntry(state.first; state.second...)
        renderArgs[state.first] = obj
        @info obj
    end
    vertexState = renderArgs[WGPUCore.GPUVertexState]
    primitiveState = renderArgs[WGPUCore.GPUPrimitiveState]
    depthStencilState = renderArgs[WGPUCore.GPUDepthStencilState]
    multiSampleState = renderArgs[WGPUCore.GPUMultiSampleState]
    fragmentState = renderArgs[WGPUCore.GPUFragmentState]
    return renderArgs
    pipelineDesc =
        WGPUCore.partialInit(
            WGPUCore.WGPURenderPipelineDescriptor;
            label = toCString(label),
            layout = pipelinelayout.internal[],
            vertex = vertexState[],
            primitive = primitiveState[],
            depthStencil = depthStencilState[],
            multisample = multiSampleState[],
            fragment = fragmentState[],
        ) |> Ref
    renderpipeline =
        WGPUCore.wgpuDeviceCreateRenderPipeline(gpuDevice.internal[], pipelineDesc) |> Ref
    return WGPUCore.GPURenderPipeline(
        label |> Ref,
        renderpipeline,
        pipelineDesc,
        gpuDevice,
        pipelinelayout,
        vertexState,
        primitiveState,
        depthStencilState,
        multiSampleState,
        fragmentState,
    )
end

renderPipeline = createRenderPipeline(
    gpuDevice,
    pipelineLayout,
    renderpipelineOptions;
    label = "RENDER PIPE LABEL ",
)

vertexAttrib1 = WGPUCore.createEntry(
    WGPUCore.GPUVertexAttribute;
    format = "Float32x4",
    offset = 0,
    shaderLocation = 0,
)


vertexAttrib2 = WGPUCore.createEntry(
    WGPUCore.GPUVertexAttribute;
    format = "Float32x2",
    offset = 16,
    shaderLocation = 1,
)


Test.@testset "RenderPipeline" begin
    renderFragment = renderPipeline[WGPUCore.GPUFragmentState]
    fs = unsafe_load(renderFragment.internal[] |> ptr)
    Test.@test unsafe_string(fs.entryPoint) == "fs_main"

    fsColorTarget = unsafe_load(fs.targets)
    Test.@test fsColorTarget.format == WGPUCore.getEnum(WGPUCore.WGPUTextureFormat, "BGRA8Unorm")

    Test.@test fsColorTarget.writeMask == 0x0000000f
    fsblend = unsafe_load(fsColorTarget.blend)
    # fsblend .alpha = WGPUCore.createEntry(WGPUCore.GPUBlendComponent)
    # Check if shader module is alive
    Test.@test fs._module != C_NULL
    Test.@test fs._module == cshader.internal[]

    renderVertex = renderPipeline[WGPUCore.GPUVertexState]
    vs = renderVertex.internal[]
    buf = unsafe_load(vs.buffers)
    attrs =
        unsafe_wrap(Vector{WGPUCore.WGPUVertexAttribute}, buf.attributes, buf.attributeCount)
    attr1 = unsafe_load(buf.attributes, 1)
    attr2 = unsafe_load(buf.attributes, 2)
    buf1 = unsafe_wrap(Vector{WGPUCore.WGPUVertexBufferLayout}, vs.buffers, vs.bufferCount)
    # check if buffers is alive
    Test.@test vs.buffers != C_NULL
    Test.@test attr1 == vertexAttrib1.internal |> concrete
    Test.@test attrs == [attr1, attr2]
    Test.@test attr2 == vertexAttrib2.internal |> concrete

end

# renderPipeline = nothing
