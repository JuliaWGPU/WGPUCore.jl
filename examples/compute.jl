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
stagingLabel = "StagingBuffer"

stagingBuffer = wgpuDeviceCreateBuffer(
    device.internal[],
    cStruct(
        WGPUBufferDescriptor;
        nextInChain = C_NULL,
        label = WGPUStringView(pointer(stagingLabel), length(stagingLabel)),
        usage = (WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst) |> WGPUBufferUsage,
        size = sizeof(numbers),
        mappedAtCreation = false
    ) |> ptr
)
## StorageBuffer 
storageLabel = "StorageBuffer"
storageBuffer = wgpuDeviceCreateBuffer(
    device.internal[], 
    cStruct(
        WGPUBufferDescriptor;
        nextInChain = C_NULL,
        label = WGPUStringView(pointer(storageLabel), length(storageLabel)),
        usage = WGPUBufferUsage( WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst | WGPUBufferUsage_CopySrc ),
        size = sizeof(numbers),
        mappedAtCreation = false
    ) |> ptr
)

entries = WGPUBindGroupLayoutEntry[]

entry = WGPUBindGroupLayoutEntry |> CStruct 


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
)

bglayoutDescLabel = "Bind Group Layout"
layoutdesc = cStruct(
    WGPUBindGroupLayoutDescriptor;
    label = WGPUStringView(pointer(bglayoutDescLabel), length(bglayoutDescLabel)),
    entries = entries |> ptr,
    entryCount = 1
) 

## BindGroupLayout
bindGroupLayout = wgpuDeviceCreateBindGroupLayout(
    device.internal[],
    layoutdesc |> ptr
)

## BindGroup

bgLabel = "Bind Group"
bindGroup = wgpuDeviceCreateBindGroup(
    device.internal[],
    cStruct(
        WGPUBindGroupDescriptor;
        label = WGPUStringView(pointer(bgLabel), length(bgLabel)),
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

computeLabel = "compute main"
compute = cStruct(
    WGPUProgrammableStageDescriptor;
    _module = shader,
    entryPoint = WGPUStringView(pointer(computeLabel), length(computeLabel))
) |> concrete


## compute pipeline
computePipelineLabel = "main"
computePipeline = wgpuDeviceCreateComputePipeline(
    device.internal[],
    cStruct(
        WGPUComputePipelineDescriptor,
        layout = pipelineLayout,
        compute = cStruct(
            WGPUProgrammableStageDescriptor;
            _module = shader,
            entryPoint = WGPUStringView(pointer(computePipelineLabel), length(computePipelineLabel))
        ) |> concrete
    ) |> ptr
)

## encoder
cmdEncoderLabel = "Command Encoder"
encoder = wgpuDeviceCreateCommandEncoder(
            device.internal[],
            cStruct(
                WGPUCommandEncoderDescriptor;
                label = WGPUStringView(pointer(cmdEncoderLabel), length(cmdEncoderLabel))
            ) |> ptr
        )


## computePass
computePassLabel = "Compute Pass"
computePass = wgpuCommandEncoderBeginComputePass(
    encoder,
    cStruct(
        WGPUComputePassDescriptor;
        label = WGPUStringView(pointer(computePassLabel), length(computePassLabel))
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

asyncstatus = Ref(WGPUMapAsyncStatus(3))

function readBufferMap(
        status::WGPUMapAsyncStatus,
        userData)
    asyncstatus[] = status
    return nothing
end

readbuffermap = @cfunction(readBufferMap, Cvoid, (WGPUMapAsyncStatus, Ptr{Cvoid}))
readBufferMapInfo = WGPUBufferMapCallbackInfo |> CStruct
readBufferMapInfo.callback = readbuffermap

wgpuBufferMapAsync(stagingBuffer, WGPUMapMode_Read, 0, sizeof(numbers), readBufferMapInfo |> concrete)

print(asyncstatus[])

## device polling

wgpuDevicePoll(device.internal[], true, C_NULL)

## times
times = convert(Ptr{UInt32}, wgpuBufferGetMappedRange(stagingBuffer, 0, sizeof(numbers)))

## result
for i in eachindex(numbers)
    println(numbers[i], " : " ,unsafe_load(times, i))
end


