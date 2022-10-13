## Load WGPU
using WGPUCore

using WGPUNative

WGPUCore.SetLogLevel(WGPULogLevel_Debug)

src = """
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

shaderSource = Vector{UInt8}(src);
n = 20

data = Array{UInt8,1}(undef, n)

for i = 1:n
    data[i] = i
end

# canvas = WGPUCore.defaultCanvas(WGPUCore.WGPUCanvas);
gpuDevice = WGPUCore.getDefaultDevice()

shadercode = WGPUCore.loadWGSL(shaderSource) |> first

cshader =
    WGPUCore.createShaderModule(gpuDevice, "shadercode", shadercode, nothing, nothing) |> Ref

(buffer1, _) = WGPUCore.createBufferWithData(gpuDevice, "buffer1", data, "Storage")

buffer2 =
    WGPUCore.createBuffer("buffer2", gpuDevice, sizeof(data), ["Storage", "CopySrc"], false)

bindingLayouts = [
    WGPUCore.WGPUBufferEntry =>
        [:binding => 0, :visibility => "Compute", :type => "ReadOnlyStorage"],
    WGPUCore.WGPUBufferEntry =>
        [:binding => 1, :visibility => "Compute", :type => "Storage"],
]

bindings = [
    WGPUCore.GPUBuffer =>
        [:binding => 0, :buffer => buffer1, :offset => 0, :size => buffer1.size],
    WGPUCore.GPUBuffer =>
        [:binding => 1, :buffer => buffer2, :offset => 0, :size => buffer2.size],
]


(bindGroupLayouts, bindGroup) =
    WGPUCore.makeBindGroupAndLayout(gpuDevice, bindingLayouts, bindings)

pipelineLayout = WGPUCore.createPipelineLayout(gpuDevice, "PipeLineLayout", bindGroupLayouts)
computeStage = WGPUCore.createComputeStage(cshader[], "main")
computePipeline =
    WGPUCore.createComputePipeline(gpuDevice, "computePipeline", pipelineLayout, computeStage)

commandEncoder = WGPUCore.createCommandEncoder(gpuDevice, "Command Encoder")
computePass = WGPUCore.beginComputePass(commandEncoder)
# 
WGPUCore.setPipeline(computePass, computePipeline)
WGPUCore.setBindGroup(computePass, 0, bindGroup, UInt32[], 0, 99999)
WGPUCore.dispatchWorkGroups(computePass, n, 1, 1)
WGPUCore.endComputePass(computePass)
WGPUCore.submit(gpuDevice.queue, [WGPUCore.finish(commandEncoder)])
WGPUCore.readBuffer(gpuDevice, buffer2, 0, sizeof(data))
