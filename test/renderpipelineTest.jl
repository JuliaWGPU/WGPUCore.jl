## Load WGPU
using WGPU
using Test
using WGPU_jll
using GLFW

WGPU.SetLogLevel(WGPULogLevel_Debug)

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
) |> Ref

canvas = WGPU.defaultInit(WGPU.GLFWX11Canvas);
gpuDevice = WGPU.getDefaultDevice();
shadercode = WGPU.loadWGSL(shaderSource[]) |> first;
cshader = WGPU.createShaderModule(gpuDevice, "shadercode", shadercode, nothing, nothing);
cshaderRef = cshader |> Ref

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


renderpipelineOptions = [
	WGPU.GPUVertexState => [
		:_module => cshaderRef[],
		:entryPoint => "vs_main",
		:buffers => [
			WGPU.GPUVertexBufferLayout => [
				:arrayStride => 6*4,
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
		:_module => cshaderRef[],
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

function createRenderPipeline(
	gpuDevice, 
	pipelinelayout, 
	renderpipeline;
	label="RenderPipeLine"
)
	renderArgs = Dict()
	for state in renderpipeline
		obj = WGPU.createEntry(state.first; state.second...)
		renderArgs[state.first] = obj
		@info obj
	end
	vertexState = renderArgs[WGPU.GPUVertexState].internal
	primitiveState = renderArgs[WGPU.GPUPrimitiveState].internal
	depthStencilState = renderArgs[WGPU.GPUDepthStencilState].internal
	multiSampleState = renderArgs[WGPU.GPUMultiSampleState].internal
	fragmentState = renderArgs[WGPU.GPUFragmentState].internal
	return renderArgs
	pipelineDesc = WGPU.partialInit(
			WGPU.WGPURenderPipelineDescriptor;
			label = pointer(label),
			layout = pipelinelayout.internal[],
			vertex = vertexState[],
			primitive = primitiveState[],
			depthStencil = depthStencilState[],
			multisample = multiSampleState[],
			fragment = fragmentState[]
		) |> Ref
	renderpipeline =  WGPU.wgpuDeviceCreateRenderPipeline(
		gpuDevice.internal[],
		pipelineDesc
	) |> Ref
	return WGPU.GPURenderPipeline(
		label |> Ref,
		renderpipeline,
		pipelineDesc,
		gpuDevice, 
		pipelinelayout , 
		vertexState , 
		primitiveState , 
		depthStencilState , 
		multiSampleState , 
		fragmentState 
	)
end

renderPipeline =  createRenderPipeline(
	gpuDevice, pipelineLayout, 
	renderpipelineOptions; 
	label = "RENDER PIPE LABEL "
)

Test.@testset "RenderPipeline" begin
	renderFragment = renderPipeline[WGPU.GPUFragmentState]
	fs = unsafe_load(renderFragment.internal[])
	Test.@test unsafe_string(fs.entryPoint) == "fs_main"

	fsColorTarget = unsafe_load(fs.targets)
	Test.@test fsColorTarget.format == WGPU.getEnum(WGPU.WGPUTextureFormat, "BGRA8UnormSrgb")

	Test.@test fsColorTarget.writeMask == 0x0000000f
	fsblend = unsafe_load(fsColorTarget.blend)
	# fsblend .alpha = WGPU.createEntry(WGPU.GPUBlendComponent)
	# Check if shader module is alive
	Test.@test fs._module != C_NULL
	Test.@test fs._module == cshader.internal[]

	renderVertex = renderPipeline[WGPU.GPUVertexState]
	vs = renderVertex.internal[]

	# check if buffers is alive
	Test.@test vs.buffers != C_NULL

end

GLFW.DestroyWindow(canvas.windowRef[])
