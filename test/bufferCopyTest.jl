## Load WGPU
using WGPUCore
using Test

using WGPUNative

WGPUCore.SetLogLevel(WGPULogLevel_Debug)

n = 20

data = Array{UInt8,1}(undef, n)

for i = 1:n
    data[i] = i
end

canvas = WGPUCore.getCanvas();

gpuDevice = WGPUCore.getDefaultDevice(canvas)

# GC.gc()

(buffer1, _) =
    WGPUCore.createBufferWithData(gpuDevice, "buffer1", data, ["Storage", "CopyDst", "CopySrc"])

buffer2 = WGPUCore.createBuffer(
    "buffer2",
    gpuDevice,
    sizeof(data),
    ["Storage", "CopySrc", "CopyDst"],
    false,
)

commandEncoder = WGPUCore.createCommandEncoder(gpuDevice, "Command Encoder")

WGPUCore.copyBufferToBuffer(commandEncoder, buffer1, 0, buffer2, 0, sizeof(data))
a = WGPUCore.finish(commandEncoder)
WGPUCore.submit(gpuDevice.queue, [a])

dataDown = WGPUCore.readBuffer(gpuDevice, buffer2, 0, sizeof(data))

dataDown2 = WGPUCore.readBuffer(gpuDevice, buffer1, 0, sizeof(data))

Test.@test data == dataDown

WGPUCore.destroy(buffer1)
WGPUCore.destroy(buffer2)

GC.gc(true)

# gpuDevice = nothing

WGPUCore.destroy(gpuDevice)
