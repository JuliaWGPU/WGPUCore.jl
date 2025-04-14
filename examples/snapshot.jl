## Load WGPU
using WGPUCore
using GLFW

using WGPUNative
using Images
using Debugger 

WGPUCore.SetLogLevel(WGPULogLevel_Debug)

shaderSource = Vector{UInt8}(
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
        var positions = array<vec2<f32>, 3>(vec2<f32>(0.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0));
        let index = i32(in.vertex_index);
        let p: vec2<f32> = positions[index];

        var out: VertexOutput;
        out.pos = vec4<f32>(sin(p), 0.5, 1.0);
        out.color = vec4<f32>(p, 0.5, 1.0);
        return out;
    }

    @fragment
    fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
        return in.color;
    }
    """,
);

canvas = WGPUCore.getCanvas();
gpuDevice = WGPUCore.getDefaultDevice(canvas);
shadercode = WGPUCore.loadWGSL(shaderSource);
cshader =
    Ref(WGPUCore.createShaderModule(gpuDevice, "shadercode", shadercode.shaderModuleDesc, nothing, nothing));

bindingLayouts = []
bindings = []

pipelineLayout = WGPUCore.createPipelineLayout(
    gpuDevice, 
    "PipeLineLayout",
    bindingLayouts,
    bindings 
)

# swapChainFormat = wgpuSurfaceGetPreferredFormat(canvas.surface[], gpuDevice.adapter.internal[])
swapChainFormat = WGPUCore.getPreferredFormat(canvas)
@info swapChainFormat
presentContext = WGPUCore.getContext(canvas)
ctxtSize = WGPUCore.determineSize(presentContext) .|> Int

WGPUCore.config(presentContext, device = gpuDevice, format = swapChainFormat)

renderpipelineOptions = [
    WGPUCore.GPUVertexState =>
        [:_module => cshader[], :entryPoint => "vs_main", :buffers => []],
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
        :_module => cshader[],
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

# renderPipelineLabel = "RENDER PIPE LABEL "

renderPipeline = WGPUCore.createRenderPipeline(
    gpuDevice,
    pipelineLayout,
    renderpipelineOptions;
    label = "RENDER PIPE LABEL ",
)

try
    nextTexture = WGPUCore.getCurrentTexture(presentContext)
    cmdEncoder = WGPUCore.createCommandEncoder(gpuDevice, "cmdEncoder")
    renderPassOptions =
        [
            WGPUCore.GPUColorAttachments => [
                :attachments => [
                    WGPUCore.GPUColorAttachment => [
                        :view => nextTexture,
                        :resolveTarget => C_NULL,
                        :clearValue => (0.0, 0.0, 0.0, 1.0),
                        :loadOp => WGPULoadOp_Clear,
                        :storeOp => WGPUStoreOp_Store,
                    ],
                ],
            ],
            WGPUCore.GPUDepthStencilAttachments => [],
        ] |> Ref
    renderPass =
        WGPUCore.beginRenderPass(cmdEncoder, renderPassOptions; label = "Begin Render Pass")
    WGPUCore.setPipeline(renderPass, renderPipeline)
    WGPUCore.draw(renderPass, 3; instanceCount = 1, firstVertex = 0, firstInstance = 0)
    WGPUCore.endEncoder(renderPass)
    data = WGPUCore.readTexture(gpuDevice,  presentContext)
    WGPUCore.submit(gpuDevice.queue, [WGPUCore.finish(cmdEncoder)])
    WGPUCore.present(presentContext)
    datareshaped = reshape(data, (4, ((512, 500) |> reverse)...) .|> Int) #hardcoded
    img = reinterpret(RGBA{N0f8}, datareshaped) |> (x) -> reshape(x, (512, 500)) #hardcoded
    save("triangle.png", img |> adjoint)
finally
    WGPUCore.destroyWindow(canvas)
end
