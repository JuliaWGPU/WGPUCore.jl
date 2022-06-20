using WGPU
using Test

WGPU.SetLogLevel(WGPU.WGPULogLevel_Debug)

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

vertexStateOptions = [
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
]

vertexAttrib1 = WGPU.createEntry(
	WGPU.GPUVertexAttribute; 
	format="Float32x4",
	offset=0,
	shaderLocation=0
).internal[]


vertexAttrib2 = WGPU.createEntry(
	WGPU.GPUVertexAttribute; 
	format="Float32x2",
	offset=16,
	shaderLocation=1
).internal[]


vertexState = WGPU.createEntry(
	WGPU.GPUVertexState;
	vertexStateOptions...
)

buf = unsafe_load(vertexState.internal[].buffers)
attrs = unsafe_wrap(Vector{WGPU.WGPUVertexAttribute}, buf.attributes, buf.attributeCount)
attr1 = unsafe_load(buf.attributes, 1)
attr2 = unsafe_load(buf.attributes, 2)
buf1 = unsafe_wrap(Vector{WGPU.WGPUVertexBufferLayout}, vertexState.internal[].buffers, vertexState.internal[].bufferCount)

Test.@testset "VertexAttribute" begin
	Test.@test attr1 == vertexAttrib1 
	Test.@test attrs == [attr1, attr2]
	Test.@test attr2 == vertexAttrib2
end

using GLFW
GLFW.DestroyWindow(canvas.windowRef[])
