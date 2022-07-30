## Load WGPU
using WGPU
using GLFW

using WGPU_jll
using Images

WGPU.SetLogLevel(WGPULogLevel_Off)

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
	"""
);

canvas = WGPU.defaultInit(WGPU.OffscreenCanvas);
gpuDevice = WGPU.getDefaultDevice();
shadercode = WGPU.loadWGSL(shaderSource) |> first;
cshader = Ref(WGPU.createShaderModule(gpuDevice, "shadercode", shadercode, nothing, nothing));

bindingLayouts = []
bindings = []

(bindGroupLayouts, bindGroup) = WGPU.makeBindGroupAndLayout(gpuDevice, bindingLayouts, bindings)

pipelineLayout = WGPU.createPipelineLayout(gpuDevice, "PipeLineLayout", bindGroupLayouts)
# swapChainFormat = wgpuSurfaceGetPreferredFormat(canvas.surface[], gpuDevice.adapter.internal[])
swapChainFormat = WGPU.getPreferredFormat(canvas)
@info swapChainFormat
presentContext = WGPU.getContext(canvas)
ctxtSize = WGPU.determineSize(presentContext[]) .|> Int

WGPU.config(presentContext, device=gpuDevice, format = swapChainFormat)

renderpipelineOptions = [
	WGPU.GPUVertexState => [
		:_module => cshader[],
		:entryPoint => "vs_main",
		:buffers => []
	],
	WGPU.GPUPrimitiveState => [
		:topology => "TriangleList",
		:frontFace => "CCW",
		:cullMode => "None",
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
				:format => swapChainFormat,
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

# renderPipelineLabel = "RENDER PIPE LABEL "

renderPipeline =  WGPU.createRenderPipeline(
	gpuDevice, pipelineLayout, 
	renderpipelineOptions; 
	label = "RENDER PIPE LABEL "
)

function drawFunction()
	WGPU.draw(renderPass, 3, 1, 0, 0)
	WGPU.end(renderPass)
end

WGPU.attachDrawFunction(canvas, drawFunction)

try
		bufferDims = WGPU.BufferDimensions(ctxtSize...)
		bufferSize = bufferDims.padded_bytes_per_row*bufferDims.height
		outputBuffer = WGPU.createBuffer(
			"OUTPUT BUFFER",
			gpuDevice,
			bufferSize,
			["MapRead", "CopyDst", "CopySrc"],
			false
		)
		nextTexture = WGPU.getCurrentTexture(presentContext[]) |> Ref
		cmdEncoder = WGPU.createCommandEncoder(gpuDevice, "cmdEncoder")
		renderPassOptions = [
			WGPU.GPUColorAttachments => [
				:attachments => [
					WGPU.GPUColorAttachment => [
						:view => nextTexture[],
						:resolveTarget => C_NULL,
						:clearValue => (0.0, 0.0, 0.0, 1.0),
						:loadOp => WGPULoadOp_Clear,
						:storeOp => WGPUStoreOp_Store,
					],
				]
			],
		]
		renderPass = WGPU.beginRenderPass(cmdEncoder, renderPassOptions; label= "Begin Render Pass")
		WGPU.setPipeline(renderPass, renderPipeline)
		WGPU.draw(renderPass, 3; instanceCount = 1, firstVertex= 0, firstInstance=0)
		WGPU.endEncoder(renderPass)
		WGPU.copyTextureToBuffer(
			cmdEncoder,
			[
				:texture => nextTexture[],
				:mipLevel => 0,
				:origin => [
					:x => 0,
					:y => 0,
					:z => 0
				] |> Dict
			] |> Dict,
			[
				:buffer => outputBuffer,
				:layout => [
					:offset => 0,
					:bytesPerRow => bufferDims.padded_bytes_per_row,
					:rowsPerImage => 0
				] |> Dict
			] |> Dict,
			[
				:width => bufferDims.width,
				:height => bufferDims.height,
				:depthOrArrayLayers => 1
			] |> Dict
		)
		WGPU.submit(gpuDevice.queue, [WGPU.finish(cmdEncoder),])
		WGPU.present(presentContext[])
		data = WGPU.readBuffer(gpuDevice, outputBuffer, 0,  bufferSize |> Int)
		datareshaped = reshape(data, (4, (ctxtSize |>reverse)...) .|> Int)
		img = reinterpret(RGBA{N0f8}, datareshaped) |> (x) -> reshape(x, ctxtSize)
		save("triangle.png", img |> adjoint)
finally
	WGPU.destroyWindow(canvas)
end

