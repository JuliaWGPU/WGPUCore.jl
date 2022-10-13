## Load WGPU
using WGPUCore
using GLFW

using WGPUNative
using Images

WGPUCore.SetLogLevel(WGPULogLevel_Off)

shaderSource = Vector{UInt8}(
    """
    struct VertexInput {
        @builtin(vertex_index) vertex_index : u32,
    };
    struct VertexOutput {
        @location(0) color : vec4<f32>,
        @builtin(position) pos: vec4<f32>,
    };

    @stage(vertex)
    fn vs_main(in: VertexInput) -> VertexOutput {
        var positions = array<vec2<f32>, 3>(vec2<f32>(0.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0));
        let index = i32(in.vertex_index);
        let p: vec2<f32> = positions[index];

        var out: VertexOutput;
        out.pos = vec4<f32>(sin(p), 0.5, 1.0);
        out.color = vec4<f32>(p, 0.5, 1.0);
        return out;
    }

    @stage(fragment)
    fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
        return in.color;
    }
    """,
);

canvas = WGPUCore.defaultCanvas(WGPUCore.OffscreenCanvas);
gpuDevice = WGPUCore.getDefaultDevice();
shadercode = WGPUCore.loadWGSL(shaderSource) |> first;
cshader =
    Ref(WGPUCore.createShaderModule(gpuDevice, "shadercode", shadercode, nothing, nothing));

bindingLayouts = []
bindings = []

(bindGroupLayouts, bindGroup) =
    WGPUCore.makeBindGroupAndLayout(gpuDevice, bindingLayouts, bindings)

pipelineLayout = WGPUCore.createPipelineLayout(gpuDevice, "PipeLineLayout", bindGroupLayouts)
# swapChainFormat = wgpuSurfaceGetPreferredFormat(canvas.surface[], gpuDevice.adapter.internal[])
swapChainFormat = WGPUCore.getPreferredFormat(canvas)
@info swapChainFormat
presentContext = WGPUCore.getContext(canvas)
ctxtSize = WGPUCore.determineSize(presentContext[]) .|> Int

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

function drawFunction()
    WGPUCore.draw(renderPass, 3, 1, 0, 0)
    WGPUCore.end(renderPass)
end

WGPUCore.attachDrawFunction(canvas, drawFunction)

try
    bufferDims = WGPUCore.BufferDimensions(ctxtSize...)
    bufferSize = bufferDims.padded_bytes_per_row * bufferDims.height
    outputBuffer = WGPUCore.createBuffer(
        "OUTPUT BUFFER",
        gpuDevice,
        bufferSize,
        ["MapRead", "CopyDst", "CopySrc"],
        false,
    )
    nextTexture = WGPUCore.getCurrentTexture(presentContext[]) |> Ref
    cmdEncoder = WGPUCore.createCommandEncoder(gpuDevice, "cmdEncoder")
    renderPassOptions =
        [
            WGPUCore.GPUColorAttachments => [
                :attachments => [
                    WGPUCore.GPUColorAttachment => [
                        :view => nextTexture[],
                        :resolveTarget => C_NULL,
                        :clearValue => (0.0, 0.0, 0.0, 1.0),
                        :loadOp => WGPULoadOp_Clear,
                        :storeOp => WGPUStoreOp_Store,
                    ],
                ],
            ],
            WGPUCore.DepthStencilAttachments => [],
        ] |> Ref
    renderPass =
        WGPUCore.beginRenderPass(cmdEncoder, renderPassOptions; label = "Begin Render Pass")
    WGPUCore.setPipeline(renderPass, renderPipeline)
    WGPUCore.draw(renderPass, 3; instanceCount = 1, firstVertex = 0, firstInstance = 0)
    WGPUCore.endEncoder(renderPass)
    WGPUCore.copyTextureToBuffer(
        cmdEncoder,
        [
            :texture => nextTexture[],
            :mipLevel => 0,
            :origin => [:x => 0, :y => 0, :z => 0] |> Dict,
        ] |> Dict,
        [
            :buffer => outputBuffer,
            :layout =>
                [
                    :offset => 0,
                    :bytesPerRow => bufferDims.padded_bytes_per_row,
                    :rowsPerImage => 0,
                ] |> Dict,
        ] |> Dict,
        [
            :width => bufferDims.width,
            :height => bufferDims.height,
            :depthOrArrayLayers => 1,
        ] |> Dict,
    )
    WGPUCore.submit(gpuDevice.queue, [WGPUCore.finish(cmdEncoder)])
    WGPUCore.present(presentContext[])
    data = WGPUCore.readBuffer(gpuDevice, outputBuffer, 0, bufferSize |> Int)
    datareshaped = reshape(data, (4, (ctxtSize |> reverse)...) .|> Int)
    img = reinterpret(RGBA{N0f8}, datareshaped) |> (x) -> reshape(x, ctxtSize)
    save("triangle.png", img |> adjoint)
finally
    WGPUCore.destroyWindow(canvas)
end
