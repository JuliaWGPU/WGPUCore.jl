## Load WGPU
using WGPU
using Test

using WGPUNative

WGPU.SetLogLevel(WGPULogLevel_Debug)

n = 20

data = Array{UInt8,1}(undef, n)

for i = 1:n
    data[i] = i
end

canvas = WGPU.defaultInit(WGPU.WGPUCanvas);

gpuDevice = WGPU.getDefaultDevice()

# GC.gc()

(buffer1, _) =
    WGPU.createBufferWithData(gpuDevice, "buffer1", data, ["Storage", "CopyDst", "CopySrc"])

buffer2 = WGPU.createBuffer(
    "buffer2",
    gpuDevice,
    sizeof(data),
    ["Storage", "CopySrc", "CopyDst"],
    false,
)

commandEncoder = WGPU.createCommandEncoder(gpuDevice, "Command Encoder")

WGPU.copyBufferToBuffer(commandEncoder, buffer1, 0, buffer2, 0, sizeof(data))
a = WGPU.finish(commandEncoder)
WGPU.submit(gpuDevice.queue, [a])

dataDown = WGPU.readBuffer(gpuDevice, buffer2, 0, sizeof(data))

dataDown2 = WGPU.readBuffer(gpuDevice, buffer1, 0, sizeof(data))

Test.@test data == dataDown

WGPU.destroy(buffer1)
WGPU.destroy(buffer2)

GC.gc(true)

# gpuDevice = nothing

WGPU.destroy(gpuDevice[])
