## Load WGPU
using WGPU

using WGPU_jll
using GLFW

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
	    var positions = array<vec2<f32>, 3>(vec2<f32>(0.0, -0.5), vec2<f32>(0.5, 0.5), vec2<f32>(-0.5, 0.7));
	    let index = i32(in.vertex_index);
	    let p: vec2<f32> = positions[index];

	    var out: VertexOutput;
	    out.pos = vec4<f32>(sin(p), 0.0, 1.0);
	    out.color = vec4<f32>(p, 0.5, 1.0);
	    return out;
	}

	@stage(fragment)
	fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
	    return in.color;
	}
	"""
);

canvas = WGPU.defaultInit(WGPU.GLFWX11Canvas);
gpuDevice = WGPU.getDefaultDevice();
shadercode = WGPU.loadWGSL(shaderSource) |> first;
cshader = Ref(WGPU.createShaderModule(gpuDevice, "shadercode", shadercode, nothing, nothing));

bindingLayouts = []
bindings = []
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
swapChainFormat = wgpuSurfaceGetPreferredFormat(canvas.surface[], gpuDevice.adapter[])

presentContext = WGPU.getContext(canvas)
WGPU.determineSize(presentContext)

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
		nextTexture = WGPU.getCurrentTexture(presentContext) |> Ref
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
		WGPU.submit(gpuDevice.queue, [WGPU.finish(cmdEncoder),])
		WGPU.present(presentContext)
		GLFW.PollEvents()
	end
finally
	GLFW.DestroyWindow(canvas.windowRef[])
end

