## Load WGPU
using WGPU
using Test
using WGPU_jll
using GLFW

WGPU.setDebugMode(false)
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

canvas = WGPU.defaultInit(WGPU.WGPUCanvas);
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
swapChainFormat = WGPU.getPreferredFormat(canvas)


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

vertexAttrib1 = WGPU.createEntry(
	WGPU.GPUVertexAttribute; 
	format="Float32x4",
	offset=0,
	shaderLocation=0
)


vertexAttrib2 = WGPU.createEntry(
	WGPU.GPUVertexAttribute; 
	format="Float32x2",
	offset=16,
	shaderLocation=1
)


Test.@testset "RenderPipeline" begin
	renderFragment = renderPipeline[WGPU.GPUFragmentState]
	fs = unsafe_load(convert(Ptr{WGPU.WGPUFragmentState}, renderFragment.internal[]))
	Test.@test unsafe_string(fs.entryPoint) == "fs_main"

	fsColorTarget = unsafe_load(fs.targets)
	Test.@test fsColorTarget.format == WGPU.getEnum(WGPU.WGPUTextureFormat, "BGRA8Unorm")

	Test.@test fsColorTarget.writeMask == 0x0000000f
	fsblend = unsafe_load(fsColorTarget.blend)
	# fsblend .alpha = WGPU.createEntry(WGPU.GPUBlendComponent)
	# Check if shader module is alive
	Test.@test fs._module != C_NULL
	Test.@test fs._module == cshader.internal[]

	renderVertex = renderPipeline[WGPU.GPUVertexState]
	vs = renderVertex.internal[]
	buf = unsafe_load(vs.buffers)
	attrs = unsafe_wrap(Vector{WGPU.WGPUVertexAttribute}, buf.attributes, buf.attributeCount)
	attr1 = unsafe_load(buf.attributes, 1)
	attr2 = unsafe_load(buf.attributes, 2)
	buf1 = unsafe_wrap(Vector{WGPU.WGPUVertexBufferLayout}, vs.buffers, vs.bufferCount)
	# check if buffers is alive
	Test.@test vs.buffers != C_NULL
	Test.@test attr1 == vertexAttrib1.internal[] 
	Test.@test attrs == [attr1, attr2]
	Test.@test attr2 == vertexAttrib2.internal[]

end

# renderPipeline = nothing

GC.gc(true)

GLFW.DestroyWindow(canvas.windowRef[])
