using WGPUCore
using LinearAlgebra
using Rotations
using WGPUNative
using GLFW
using StaticArrays

WGPUCore.SetLogLevel(WGPULogLevel_Debug)

shaderSource = Vector{UInt8}(
	"""
	struct Locals {
	    transform: mat4x4<f32>,
	};

	@group(0) @binding(0)
	var<uniform> r_locals: Locals;

	struct VertexInput {
	    @location(0) pos : vec4<f32>,
	    @location(1) texcoord: vec2<f32>,
	};
	struct VertexOutput {
	    @location(0) texcoord: vec2<f32>,	
	    @builtin(position) pos: vec4<f32>,
	};

	@vertex
	fn vs_main(in: VertexInput) -> VertexOutput {
	    let ndc: vec4<f32> = r_locals.transform * in.pos;
	    var out: VertexOutput;
	    out.pos = vec4<f32>(ndc.x, ndc.y, 0.0, 1.0);
	    out.texcoord = in.texcoord;
	    return out;
	}

	@group(0) @binding(1)
	var r_tex: texture_2d<f32>;

	@group(0) @binding(2)
	var r_sampler: sampler;

	@fragment
	fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
	    let value = textureSample(r_tex, r_sampler, in.texcoord).r;
	    return vec4<f32>(value, value, value, 1.0);
	}
	"""
);

canvas = WGPUCore.defaultCanvas(WGPUCore.WGPUCanvas)
gpuDevice = WGPUCore.getDefaultDevice()
shadercode = WGPUCore.loadWGSL(shaderSource);
cshader =
    WGPUCore.createShaderModule(gpuDevice, "shadercode", shadercode.shaderModuleDesc, nothing, nothing);
cshaderRef = cshader |> Ref;

flatten(x) = reshape(x, (:,))

vertexData =
    cat(
        [
            [-1, -1, 1, 1, 0, 0],
            [1, -1, 1, 1, 1, 0],
            [1, 1, 1, 1, 1, 1],
            [-1, 1, 1, 1, 0, 1],
            [-1, 1, -1, 1, 1, 0],
            [1, 1, -1, 1, 0, 0],
            [1, -1, -1, 1, 0, 1],
            [-1, -1, -1, 1, 1, 1],
            [1, -1, -1, 1, 0, 0],
            [1, 1, -1, 1, 1, 0],
            [1, 1, 1, 1, 1, 1],
            [1, -1, 1, 1, 0, 1],
            [-1, -1, 1, 1, 1, 0],
            [-1, 1, 1, 1, 0, 0],
            [-1, 1, -1, 1, 0, 1],
            [-1, -1, -1, 1, 1, 1],
            [1, 1, -1, 1, 1, 0],
            [-1, 1, -1, 1, 0, 0],
            [-1, 1, 1, 1, 0, 1],
            [1, 1, 1, 1, 1, 1],
            [1, -1, 1, 1, 0, 0],
            [-1, -1, 1, 1, 1, 0],
            [-1, -1, -1, 1, 1, 1],
            [1, -1, -1, 1, 0, 1],
        ]...,
        dims = 2,
    ) .|> Float32


indexData =
    cat(
        [
            [0, 1, 2, 2, 3, 0],
            [4, 5, 6, 6, 7, 4],
            [8, 9, 10, 10, 11, 8],
            [12, 13, 14, 14, 15, 12],
            [16, 17, 18, 18, 19, 16],
            [20, 21, 22, 22, 23, 20],
        ]...,
        dims = 2,
    ) .|> UInt32


tmpData =
    cat(
        [
            [50, 100, 150, 200],
            [100, 150, 200, 50],
            [150, 200, 50, 100],
            [200, 50, 100, 150],
        ]...,
        dims = 2,
	) .|> UInt8



textureData = repeat(tmpData, inner = (64, 64))
textureSize = (size(textureData)..., 1)


uniformData = ones(Float32, (4, 4)) |> Diagonal |> Matrix


(vertexBuffer, _) =
    WGPUCore.createBufferWithData(gpuDevice, "vertexBuffer", vertexData, ["Vertex", "CopySrc"])


(indexBuffer, _) =
    WGPUCore.createBufferWithData(gpuDevice, "indexBuffer", indexData |> flatten, "Index")

(uniformBuffer, _) = WGPUCore.createBufferWithData(
    gpuDevice,
    "uniformBuffer",
    uniformData,
    ["Uniform", "CopyDst"],
)

renderTextureFormat = WGPUCore.getPreferredFormat(canvas)

texture = WGPUCore.createTexture(
    gpuDevice,
    "texture",
    textureSize,
    1,
    1,
    WGPUTextureDimension_2D,
    WGPUTextureFormat_R8Unorm,
    WGPUCore.getEnum(WGPUCore.WGPUTextureUsage, ["CopyDst", "TextureBinding"]),
)

textureView = WGPUCore.createView(texture)

dstLayout = [
    :dst => [
        :texture => texture |> Ref,
        :mipLevel => 0,
        :origin => ((0, 0, 0) .|> Float32),
    ],
    :textureData => textureData |> Ref,
    :layout => [
        :offset => 0,
        :bytesPerRow => size(textureData) |> last, # TODO
        :rowsPerImage => size(textureData) |> first,
    ],
    :textureSize => textureSize,
]

sampler = WGPUCore.createSampler(gpuDevice)

WGPUCore.writeTexture(gpuDevice.queue; dstLayout...)

bindingLayouts = [
    WGPUCore.WGPUBufferEntry =>
        [:binding => 0, :visibility => ["Vertex", "Fragment"], :type => "Uniform"],
    WGPUCore.WGPUTextureEntry => [
        :binding => 1,
        :visibility => "Fragment",
        :sampleType => "Float",
        :viewDimension => "2D",
        :multisampled => false,
    ],
    WGPUCore.WGPUSamplerEntry =>
        [:binding => 2, :visibility => "Fragment", :type => "Filtering"],
]

bindings = [
    WGPUCore.GPUBuffer => [
        :binding => 0,
        :buffer => uniformBuffer,
        :offset => 0,
        :size => uniformBuffer.size,
    ],
    WGPUCore.GPUTextureView => [:binding => 1, :textureView => textureView],
    WGPUCore.GPUSampler => [:binding => 2, :sampler => sampler],
]

(bindGroupLayouts, bindGroup) =
    WGPUCore.makeBindGroupAndLayout(gpuDevice, bindingLayouts, bindings)

pipelineLayout = WGPUCore.createPipelineLayout(gpuDevice, "PipeLineLayout", bindGroupLayouts)

presentContext = WGPUCore.getContext(canvas)

WGPUCore.determineSize(presentContext[])

WGPUCore.config(presentContext, device = gpuDevice, format = renderTextureFormat)

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
        :cullMode => "Back",
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
                :format => renderTextureFormat,
                :color => [:srcFactor => "One", :dstFactor => "Zero", :operation => "Add"],
                :alpha => [:srcFactor => "One", :dstFactor => "Zero", :operation => "Add"],
            ],
        ],
    ],
]

renderPipeline =
    WGPUCore.createRenderPipeline(gpuDevice, pipelineLayout, renderpipelineOptions; label = " ")


prevTime = time()
try
    while !GLFW.WindowShouldClose(canvas.windowRef[])
        a1 = 0.3f0
        a2 = time()
        s = 0.6f0
        ortho = s .* Matrix{Float32}(I, (3, 3))
        rotxy = RotXY(a1, a2)
        uniformData[1:3, 1:3] .= rotxy * ortho

        (tmpBuffer, _) =
            WGPUCore.createBufferWithData(gpuDevice, "ROTATION BUFFER", uniformData, "CopySrc")
        currentTextureView = WGPUCore.getCurrentTexture(presentContext[]) |> Ref
        cmdEncoder = WGPUCore.createCommandEncoder(gpuDevice, "CMD ENCODER")
        WGPUCore.copyBufferToBuffer(
            cmdEncoder,
            tmpBuffer,
            0,
            uniformBuffer,
            0,
            sizeof(uniformData),
        )

        renderPassOptions = [
            WGPUCore.GPUColorAttachments => [
                :attachments => [
                    WGPUCore.GPUColorAttachment => [
                        :view => currentTextureView[],
                        :resolveTarget => C_NULL,
                        :clearValue => (
                            abs(0.8f0 * sin(a2)),
                            abs(0.8f0 * cos(a2)),
                            0.3f0,
                            1.0f0,
                        ),
                        :loadOp => WGPULoadOp_Clear,
                        :storeOp => WGPUStoreOp_Store,
                    ],
                ],
            ],
            WGPUCore.GPUDepthStencilAttachments => [],
        ]

        renderPass = WGPUCore.beginRenderPass(
            cmdEncoder,
            renderPassOptions |> Ref;
            label = "BEGIN RENDER PASS",
        )

        WGPUCore.setPipeline(renderPass, renderPipeline)
        WGPUCore.setIndexBuffer(renderPass, indexBuffer, "Uint32")
        WGPUCore.setVertexBuffer(renderPass, 0, vertexBuffer)
        WGPUCore.setBindGroup(renderPass, 0, bindGroup, UInt32[], 0, 99)
        WGPUCore.drawIndexed(
            renderPass,
            Int32(indexBuffer.size / sizeof(UInt32));
            instanceCount = 1,
            firstIndex = 0,
            baseVertex = 0,
            firstInstance = 0,
        )
        WGPUCore.endEncoder(renderPass)
        WGPUCore.submit(gpuDevice.queue, [WGPUCore.finish(cmdEncoder)])
        WGPUCore.present(presentContext[])
        GLFW.PollEvents()
        # dataDown = reinterpret(Float32, WGPUCore.readBuffer(gpuDevice, vertexBuffer, 0, sizeof(vertexData)))
        # @info sum(dataDown .== vertexData |> flatten)
        # @info dataDown
        # println("FPS : $(1/(a2 - prevTime))")
        # WGPUCore.destroy(tmpBuffer)
        # WGPUCore.destroy(currentTextureView[])
        prevTime = a2
    end
finally
    GLFW.DestroyWindow(canvas.windowRef[])
end
