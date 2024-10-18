## Load WGPU
using WGPUCore
using WGPUNative
include("$(pkgdir(WGPUCore))/examples/requestDevice.jl")
# include("$(pkgdir(WGPUCore))/src/shader.jl")
## Constants
numbers = UInt32[1, 2, 3, 4]

const DEFAULT_ARRAY_SIZE = 256

## Init Window Size
const width = 200
const height = 200

## Print current version
println("Current Version : $(wgpuGetVersion())")

SetLogLevel(WGPULogLevel_Debug)

## WGSL loading
(shaderSource, _) = WGPUCore.load_wgsl("$(pkgdir(WGPUCore))/examples/shader.wgsl")

##
shader = wgpuDeviceCreateShaderModule(
    device.internal[],
    shaderSource |> ptr
)

## StagingBuffer 

stagingBuffer = wgpuDeviceCreateBuffer(
                    device.internal[], 
                    cStruct(
                        WGPUBufferDescriptor;
                        nextInChain = C_NULL,
                        label = toCString("StagingBuffer"),
                        usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst,
                        size = sizeof(numbers),
                        mappedAtCreation = false
                    ) |> ptr
                )
## StorageBuffer 

storageBuffer = wgpuDeviceCreateBuffer(
                    device.internal[], 
                    cStruct(
                        WGPUBufferDescriptor;
                        nextInChain = C_NULL,
                        label = toCString("StorageBuffer"),
                        usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst | WGPUBufferUsage_CopySrc,
                        size = sizeof(numbers),
                        mappedAtCreation = false
                    ) |> ptr
                )


## BindGroupLayout
bindGroupLayout = wgpuDeviceCreateBindGroupLayout(
    device.internal[],
    cStruct(
        WGPUBindGroupLayoutDescriptor;
        label = toCString("Bind Group Layout"),
        entries = cStruct(
            WGPUBindGroupLayoutEntry;
            nextInChain = C_NULL,
            binding = 0,
            visibility = WGPUShaderStage_Compute,
            buffer = cStruct(
                WGPUBufferBindingLayout;
                type=WGPUBufferBindingType_Storage
            ) |> concrete,
            sampler = cStruct(
                WGPUSamplerBindingLayout;
            ) |> concrete,
            texture = cStruct(
                WGPUTextureBindingLayout;
            ) |> concrete,
            storageTexture = cStruct(
                WGPUStorageTextureBindingLayout;        
            ) |> concrete
        ) |> ptr,
        entryCount = 1
    ) |> ptr
)

## BindGroup

bindGroup = wgpuDeviceCreateBindGroup(
    device.internal[],
    cStruct(
        WGPUBindGroupDescriptor;
        label = toCString("Bind Group"),
        layout = bindGroupLayout,
        entries = cStruct(
            WGPUBindGroupEntry;
            binding = 0,
            buffer = storageBuffer,
            offset = 0,
            size = sizeof(numbers)
        ) |> ptr,
        entryCount = 1
    ) |> ptr
)


## bindGroupLayouts 

bindGroupLayouts = [bindGroupLayout,]

## Pipeline Layout
pipelineLayout = wgpuDeviceCreatePipelineLayout(
    device.internal[],
    cStruct(
        WGPUPipelineLayoutDescriptor;
        bindGroupLayouts = pointer(bindGroupLayouts),
        bindGroupLayoutCount = 1
    ) |> ptr
)

## TODO fix

compute = cStruct(
    WGPUProgrammableStageDescriptor;
    _module = shader,
    entryPoint = toCString("main")
) |> concrete


## compute pipeline

computePipeline = wgpuDeviceCreateComputePipeline(
    device.internal[],
    cStruct(
        WGPUComputePipelineDescriptor,
        layout = pipelineLayout,
        compute = cStruct(
            WGPUProgrammableStageDescriptor;
            _module = shader,
            entryPoint = toCString("main")
        ) |> concrete
    ) |> ptr
)

## encoder

encoder = wgpuDeviceCreateCommandEncoder(
            device.internal[],
            cStruct(
                WGPUCommandEncoderDescriptor;
                label = toCString("Command Encoder")
            ) |> ptr
        )


## computePass
computePass = wgpuCommandEncoderBeginComputePass(
    encoder,
    cStruct(
        WGPUComputePassDescriptor;
        label = toCString("Compute Pass")
    ) |> ptr
)


## set pipeline
wgpuComputePassEncoderSetPipeline(computePass, computePipeline)
wgpuComputePassEncoderSetBindGroup(computePass, 0, bindGroup, 0, C_NULL)
wgpuComputePassEncoderDispatchWorkgroups(computePass, length(numbers), 1, 1)
wgpuComputePassEncoderEnd(computePass)
wgpuComputePassEncoderRelease(computePass)

## buffer copy buffer
wgpuCommandEncoderCopyBufferToBuffer(encoder, storageBuffer, 0, stagingBuffer, 0, sizeof(numbers))

## queue
queue = wgpuDeviceGetQueue(device.internal[])

## commandBuffer
cmdBuffer = wgpuCommandEncoderFinish(
    encoder,
    cStruct(WGPUCommandBufferDescriptor) |> ptr
)


## writeBuffer
wgpuQueueWriteBuffer(queue, storageBuffer, 0, pointer(numbers), sizeof(numbers))


## submit queue

wgpuQueueSubmit(queue, 1, Ref(cmdBuffer))

## MapAsync

asyncstatus = Ref(WGPUBufferMapAsyncStatus(3))

function readBufferMap(
        status::WGPUBufferMapAsyncStatus,
        userData)
    asyncstatus[] = status
    return nothing
end

readbuffermap = @cfunction(readBufferMap, Cvoid, (WGPUBufferMapAsyncStatus, Ptr{Cvoid}))

wgpuBufferMapAsync(stagingBuffer, WGPUMapMode_Read, 0, sizeof(numbers), readbuffermap, C_NULL)

print(asyncstatus[])

## device polling

wgpuDevicePoll(device.internal[], true, C_NULL)

## times
times = convert(Ptr{UInt32}, wgpuBufferGetMappedRange(stagingBuffer, 0, sizeof(numbers)))

## result
for i in eachindex(numbers)
    println(numbers[i], " : " ,unsafe_load(times, i))
end


