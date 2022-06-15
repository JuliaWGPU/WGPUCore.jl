using OhMyREPL
using Eyeball
using WGPU
using GeometryBasics
using LinearAlgebra
using Rotations
using WGPU_jll
using GLFW

WGPU.SetLogLevel(WGPULogLevel_Off)

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

	@stage(vertex)
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

	@stage(fragment)
	fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
	    let value = textureSample(r_tex, r_sampler, in.texcoord).r;
	    return vec4<f32>(value, value, value, 1.0);
	}
	"""
);

canvas = WGPU.defaultInit(WGPU.GLFWX11Canvas);
gpuDevice = WGPU.getDefaultDevice();
shadercode = WGPU.loadWGSL(shaderSource) |> first;
cshader = Ref(WGPU.createShaderModule(gpuDevice, "shadercode", shadercode, nothing, nothing));

flatten(x) = reshape(x, (:,))

vertexData =  cat([
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
   ]..., dims=2) .|> Float32
   
indexData =   cat([
        [0, 1, 2, 2, 3, 0], 
        [4, 5, 6, 6, 7, 4],  
        [8, 9, 10, 10, 11, 8], 
        [12, 13, 14, 14, 15, 12], 
        [16, 17, 18, 18, 19, 16], 
        [20, 21, 22, 22, 23, 20], 
    ]..., dims=2) .|> UInt32

textureData = cat([
        [50, 100, 150, 200],
        [100, 150, 200, 50],
        [150, 200, 50, 100],
        [200, 50, 100, 150],
    ]..., dims=2) .|> UInt8

textureData = repeat(textureData, inner=(64, 64))
textureSize = (size(textureData)..., 1)

# uniformData = zeros(Float32, (4, 4))
# 
# struct UniformSend
	# transform::Matrix{Float32}
# end

uniformData = Matrix{Float32}(I, (4, 4))

vertexBuffer = WGPU.createBufferWithData(
	gpuDevice, 
	"vertexBuffer", 
	vertexData, 
	"Vertex"
)

indexBuffer = WGPU.createBufferWithData(
	gpuDevice, 
	"indexBuffer", 
	indexData |> flatten, 
	"Index"
)

uniformBuffer = WGPU.createBufferWithData(
	gpuDevice, 
	"uniformBuffer", 
	uniformData, 
	["Uniform", "CopyDst"]
)

renderTextureFormat = wgpuSurfaceGetPreferredFormat(canvas.surface[], gpuDevice.adapter[])

texture = WGPU.createTexture(
	gpuDevice,
	"texture", 
	textureSize, 
	1,
	1, 
	WGPUTextureDimension_2D,  
	WGPUTextureFormat_R8Unorm,  
	WGPU.getEnum(WGPU.WGPUTextureUsage, ["CopyDst", "TextureBinding"]),
)

textureView = WGPU.createView(texture)

dstLayout = [
	:dst => [
		:texture => texture |> Ref,
		:mipLevel => 0,
		:origin => (0, 0, 0) .|> Float32
	],
	:textureData => textureData |> Ref,
	:layout => [
		:offset => 0,
		:bytesPerRow => size(textureData) |> last, # TODO
		:rowsPerImage => size(textureData) |> first
	],
	:textureSize => textureSize
]

sampler = WGPU.createSampler(gpuDevice)

WGPU.writeTexture(gpuDevice.queue; dstLayout...)

bindingLayouts = [
	WGPU.WGPUBufferEntry => [
		:binding => 0,
		:visibility => ["Vertex", "Fragment"],
		:type => "Uniform"
	],
	WGPU.WGPUTextureEntry => [
		:binding => 1,
		:visibility => "Fragment",
		:sampleType => "Float",
		:viewDimension => "2D",
		:multisampled => false
	],
	WGPU.WGPUSamplerEntry => [
		:binding => 2,
		:visibility => "Fragment",
		:type => "Filtering"
	]
]

bindings = [
	WGPU.GPUBuffer => [
		:binding => 0,
		:buffer => uniformBuffer,
		:offset => 0,
		:size => uniformBuffer.size
	],
	WGPU.GPUTextureView =>	[
		:binding => 1,
		:textureView => textureView
	],
	WGPU.GPUSampler => [
		:binding => 2,
		:sampler => sampler
	]
]

cBindingLayoutsList = Ref(WGPU.makeEntryList(bindingLayouts))
cBindingsList = Ref(WGPU.makeBindGroupEntryList(bindings))
bindGroupLayout = WGPU.createBindGroupLayout(gpuDevice, "Bind Group Layout", cBindingLayoutsList[])
bindGroup = WGPU.createBindGroup("BindGroup", gpuDevice, bindGroupLayout, cBindingsList[])

if bindGroupLayout.internal[] == C_NULL
	bindGroupLayouts = C_NULL
else
	bindGroupLayouts = map((x)->x.internal[], [bindGroupLayout,])
end

pipelineLayout = WGPU.createPipelineLayout(gpuDevice, "PipeLineLayout", bindGroupLayouts)

presentContext = WGPU.getContext(canvas)
WGPU.determineSize(presentContext)

WGPU.config(presentContext, device=gpuDevice, format = renderTextureFormat)

renderpipelineOptions = [
	WGPU.GPUVertexState => [
		:_module => cshader[],
		:entryPoint => "vs_main",
		:buffers => [
			WGPU.GPUVertexBufferLayout => [
				:arrayStride => 4*6,
				:stepMode => "Vertex",
				:attributes => [
					:attribute => [
						:format => "Float32x4",
						:offset => 0,
						:shaderLocation => 0
					],
					:attribute => [
						:format => "Float32x2",
						:offset => 4*4,
						:shaderLocation => 1
					]
				]
			],
		]
	],
	WGPU.GPUPrimitiveState => [
		:topology => "TriangleList",
		:frontFace => "CCW",
		:cullMode => "Back",
		:stripIndexFormat => "Undefined"
	],
	WGPU.GPUDepthStencilState => [],
	WGPU.GPUMultiSampleState => [
		:count => 1,
		:mask => typemax(UInt32),
		:alphaToCoverageEnabled=>false
	],
	WGPU.GPUFragmentState => [
		:_module => cshader[],
		:entryPoint => "fs_main",
		:targets => [
			WGPU.GPUColorTargetState =>	[
				:format => renderTextureFormat,
				:color => [
					:srcFactor => "One",
					:dstFactor => "Zero",
					:operation => "Add"
				],
				:alpha => [
					:srcFactor => "One",
					:dstFactor => "Zero",
					:operation => "Add",
				]
			],
		]
	]
]

renderPipeline = WGPU.createRenderPipelineFromPairs(
	gpuDevice, pipelineLayout, 
	renderpipelineOptions; 
	label=" "
)

function drawFunction()
	WGPU.draw(renderPass, 3, 1, 0, 0)
	WGPU.end(renderPass)
end

WGPU.attachDrawFunction(canvas, drawFunction)

try
	while !GLFW.WindowShouldClose(canvas.windowRef[])
		a1 = 0.3
		a2 = time()
		s = 0.6
		ortho = s*Matrix{Float32}(I, (3, 3))
		rotxy = RotXY(a1, a2)
		uniformData[1:3, 1:3] .= rotxy*ortho
		tmpBuffer = WGPU.createBufferWithData(
			gpuDevice, "rotionBuffer", uniformData, "CopySrc"
		)
		
		nextTexture = WGPU.getCurrentTexture(presentContext) |> Ref
		cmdEncoder = WGPU.createCommandEncoder(gpuDevice, "cmdEncoder")
		WGPU.copyBufferToBuffer(cmdEncoder, tmpBuffer, 0, uniformBuffer, 0, sizeof(uniformBuffer))
		renderPassOptions = [
			WGPU.GPUColorAttachments => [
				:attachments => [
					WGPU.GPUColorAttachment => [
						:view => nextTexture[],
						:resolveTarget => C_NULL,
						:clearValue => (0.2, 0.2, 0.3, 1.0),
						:loadOp => WGPULoadOp_Clear,
						:storeOp => WGPUStoreOp_Store,
					],
				]
			],
		]
		renderPass = WGPU.beginRenderPass(cmdEncoder, renderPassOptions; label= "Begin Render Pass")
		WGPU.setPipeline(renderPass, renderPipeline)
		WGPU.setIndexBuffer(renderPass, indexBuffer, "Uint32")
		WGPU.setVertexBuffer(renderPass, 0, vertexBuffer)
		WGPU.setBindGroup(renderPass, 0, bindGroup, UInt32[], 0, 99 )
		WGPU.drawIndexed(renderPass, indexBuffer.size/sizeof(UInt32); instanceCount = 1, firstIndex=0, baseVertex= 0, firstInstance=0, )
		WGPU.endEncoder(renderPass)
		WGPU.submit(gpuDevice.queue, [WGPU.finish(cmdEncoder),])
		WGPU.present(presentContext)
		GLFW.PollEvents()

	end

finally
	GLFW.DestroyWindow(canvas.windowRef[])
end

