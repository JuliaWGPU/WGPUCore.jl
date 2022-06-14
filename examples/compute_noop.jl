## Load WGPU
using WGPU

using WGPU_jll

WGPU.SetLogLevel(WGPULogLevel_Debug)

shaderSource = Vector{UInt8}(
	"""
	@group(0) @binding(0)
	var<storage, read> data1: array<i32>;

	@group(0) @binding(1)
	var<storage, read_write> data2: array<i32>;

	@stage(compute)
	@workgroup_size(1)
	fn main(@builtin(global_invocation_id) index: vec3<u32>) {
		let i: u32 = index.x;
		data2[i] = data1[i];
	}
	"""
);


n = 20

data = Array{UInt8, 1}(undef, n)

for i in 1:n
	data[i] = i
end

gpuDevice = WGPU.getDefaultDevice()

shadercode = WGPU.loadWGSL(shaderSource) |> first

cshader = Ref(WGPU.createShaderModule(gpuDevice, "shadercode", shadercode, nothing, nothing))

buffer1 = WGPU.createBufferWithData(gpuDevice, "buffer1", data, "Storage")

buffer2 = WGPU.createBuffer("buffer2", gpuDevice, 
							sizeof(data), 
							["Storage", "CopySrc"],
							false)

bindingLayouts = [
	WGPU.WGPUBufferEntry => [
		:binding => 0,
		:visibility => "Compute",
		:type =>"ReadOnlyStorage"
	],
	WGPU.WGPUBufferEntry => [
		:binding => 1,
		:visibility => "Compute",
		:type => "Storage"
	]
]

bindings = [
	WGPU.GPUBuffer => [
		:binding => 0,
		:buffer => buffer1,
		:offset => 0,
		:size => buffer1.size
	],
	WGPU.GPUBuffer =>	[
		:binding => 1,
		:buffer => buffer2,
		:offset => 0,
		:size => buffer2.size
	]
]

cBindingLayoutsList = Ref(WGPU.makeEntryList(bindingLayouts))
cBindingsList = Ref(WGPU.makeBindGroupEntryList(bindings))

bindGroupLayout = WGPU.createBindGroupLayout(gpuDevice, "Bind Group Layout", cBindingLayoutsList[])
bindGroup = WGPU.createBindGroup("BindGroup", gpuDevice, bindGroupLayout, cBindingsList[])
bindGroupLayouts = Ref(map((x)->x.internal[], [bindGroupLayout,]))

pipelineLayout = WGPU.createPipelineLayout(gpuDevice, "PipeLineLayout", bindGroupLayouts[])
computeStage = WGPU.createComputeStage(cshader[], "main")
computePipeline = WGPU.createComputePipeline(gpuDevice, "computePipeline", pipelineLayout, computeStage)

commandEncoder = WGPU.createCommandEncoder(gpuDevice, "Command Encoder")
computePass = WGPU.beginComputePass(commandEncoder)

WGPU.setPipeline(computePass, computePipeline)
WGPU.setBindGroup(computePass, 0, bindGroup, UInt32[], 0, 999999)
WGPU.dispatchWorkGroups(computePass, n, 1, 1)
WGPU.endComputePass(computePass)
WGPU.submit(gpuDevice.queue, [WGPU.finish(commandEncoder),])
WGPU.readBuffer(gpuDevice, buffer2, 0, sizeof(data))
