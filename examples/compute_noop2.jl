## Load WGPU
using WGPUCore

using WGPUNative

WGPUCore.SetLogLevel(WGPULogLevel_Debug)

shaderSource = Vector{UInt8}(
    """
    @group(0)
    @binding(0)
    var<storage, read_write> v_indices: array<u32>;  // this is used as both input and output for convenience

    // The Collatz Conjecture states that for any integer n:
    // If n is even, n = n/2
    // If n is odd, n = 3n+1
    // And repeat this process for each new n, you will always eventually reach 1.
    // Though the conjecture has not been proven, no counterexample has ever been found.
    // This function returns how many times this recurrence needs to be applied to reach 1.
    fn collatz_iterations(n_base: u32) -> u32{
        var n: u32 = n_base;
        var i: u32 = 0u;
        loop {
            if (n <= 1u) {
                break;
            }
            if (n % 2u == 0u) {
                n = n / 2u;
            }
            else {
                // Overflow? (i.e. 3*n + 1 > 0xffffffffu?)
                if (n >= 1431655765u) {   // 0x55555555u
                    return 4294967295u;   // 0xffffffffu
                }

                n = 3u * n + 1u;
            }
            i = i + 1u;
        }
        return i;
    }

    @stage(compute)
    @workgroup_size(1)
    fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
        v_indices[global_id.x] = collatz_iterations(v_indices[global_id.x]);
    }

    """,
);

n = 4

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

WGPUCore.setPipeline(computePass, computePipeline)
WGPUCore.setBindGroup(computePass, 0, bindGroup, UInt32[], 0, 999999)
WGPUCore.dispatchWorkGroups(computePass, n, 1, 1)
WGPUCore.endComputePass(computePass)
WGPUCore.submit(gpuDevice.queue, [WGPUCore.finish(commandEncoder)])
WGPUCore.readBuffer(gpuDevice, buffer2, 0, sizeof(data))
