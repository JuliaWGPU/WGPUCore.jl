## Load WGPU
using WGPU
using Test
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
	}s

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

fStateOptions = WGPU.GPUFragmentState => [
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

fstate = WGPU.createEntry(fStateOptions.first; fStateOptions.second...)

fs = unsafe_load(fstate.internal[])

Test.@testset "FragmentState" begin
	Test.@test unsafe_string(fs.entryPoint) == "fs_main"
end


GLFW.DestroyWindow(canvas.windowRef[])
