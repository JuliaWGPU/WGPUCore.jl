## Load WGPU
using WGPUCore
using WGPUCore: defaultInit, partialInit, pointerRef, SetLogLevel, toCString
using WGPUNative

## Constants
numbers = UInt32[1, 2, 3, 4]

const DEFAULT_ARRAY_SIZE = 256

## Init Window Size
const width = 200
const height = 200

## Print current version
println("Current Version : $(wgpuGetVersion())")

SetLogLevel(WGPULogLevel_Debug)
## 
adapter = Ref(WGPUAdapter())
device = Ref(WGPUDevice())

adapterOptions = cStruct(WGPURequestAdapterOptions)

function request_adapter_callback(
    a::WGPURequestAdapterStatus,
    b::WGPUAdapter,
    c::Ptr{Cchar},
    d::Ptr{Nothing},
)
    global adapter[] = b
    return nothing
end

requestAdapterCallback = @cfunction(
    request_adapter_callback,
    Cvoid,
    (WGPURequestAdapterStatus, WGPUAdapter, Ptr{Cchar}, Ptr{Cvoid})
)

## device callback
function request_device_callback(
    a::WGPURequestDeviceStatus,
    b::WGPUDevice,
    c::Ptr{Cchar},
    d::Ptr{Nothing},
)
    global device[] = b
    return nothing
end

requestDeviceCallback = @cfunction(
    request_device_callback,
    Cvoid,
    (WGPURequestDeviceStatus, WGPUDevice, Ptr{Cchar}, Ptr{Cvoid})
)

instance = wgpuCreateInstance(WGPUInstanceDescriptor(0) |> Ref)
## request adapter 

wgpuInstanceRequestAdapter(instance, adapterOptions |> ptr, requestAdapterCallback, adapter)

wgpuAdapterRequestDevice(adapter[], C_NULL, requestDeviceCallback, device[])


##
b = read(pkgdir(WGPUCore) * "/examples/shader.wgsl")
wgslDescriptor = WGPUShaderModuleWGSLDescriptor(defaultInit(WGPUChainedStruct), pointer(b))

## WGSL loading

shaderSource = WGPUCore.loadWGSL(open(pkgdir(WGPUCore) * "/examples/shader.wgsl")) |> first

##

shader = wgpuDeviceCreateShaderModule(device[], (shaderSource) |> ptr)

## StagingBuffer 
stagingBuffer = wgpuDeviceCreateBuffer(
    device[],
	cStruct(
            WGPUBufferDescriptor;
            nextInChain = C_NULL,
            label = toCString("StagingBuffer"),
            usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst,
            size = sizeof(numbers),
            mappedAtCreation = false,
    ) |> ptr,
)

## StorageBuffer 
storageBuffer = wgpuDeviceCreateBuffer(
    device[],
    cStruct(
	    WGPUBufferDescriptor;
	    nextInChain = C_NULL,
	    label = toCString("StorageBuffer"),
	    usage = WGPUBufferUsage_Storage |
	            WGPUBufferUsage_CopyDst |
	            WGPUBufferUsage_CopySrc,
	    size = sizeof(numbers),
	    mappedAtCreation = false,
    ) |> ptr,
)

bufBindingLayout = cStruct(
    WGPUBufferBindingLayout;
    type = WGPUBufferBindingType_Storage,
)

lentry = cStruct(
    WGPUBindGroupLayoutEntry;
    nextInChain = C_NULL,
    binding = 0,
    visibility = WGPUShaderStage_Compute,
    buffer = bufBindingLayout |> ptr |> unsafe_load,
    sampler = cStruct(
    	WGPUSamplerBindingLayout;
    ) |> ptr |> unsafe_load,
    texture = cStruct(
    	WGPUTextureBindingLayout;
    ) |> ptr |> unsafe_load,
    storageTexture = cStruct(
    	WGPUStorageTextureBindingLayout;
    ) |> ptr |> unsafe_load
) |> ptr |> unsafe_load

## BindGroupLayout
bindGroupLayout = wgpuDeviceCreateBindGroupLayout(
    device[],
    cStruct(
        WGPUBindGroupLayoutDescriptor;
        label = toCString("Bind Group Layout"),
        entries = pointer([
            lentry,
        ]),
        entryCount = 1,
    ) |> ptr,
)

## BindGroup
bindGroup = wgpuDeviceCreateBindGroup(
    device[],
    cStruct(
        WGPUBindGroupDescriptor;
        label = toCString("Bind Group"),
        layout = bindGroupLayout,
        entries = pointer([
            cStruct(
                WGPUBindGroupEntry;
                binding = 0,
                buffer = storageBuffer,
                offset = 0,
                size = sizeof(numbers),
            ) |> ptr |> unsafe_load,
        ]),
        entryCount = 1,
    ) |> ptr,
)


## bindGroupLayouts 
bindGroupLayouts = [bindGroupLayout]

## Pipeline Layout
pipelineLayout = wgpuDeviceCreatePipelineLayout(
    device[],
    cStruct(
        WGPUPipelineLayoutDescriptor;
        bindGroupLayouts = pointer(bindGroupLayouts),
        bindGroupLayoutCount = 1,
    ) |> ptr,
)


## compute pipeline
computePipeline = wgpuDeviceCreateComputePipeline(
    device[],
    cStruct(
        WGPUComputePipelineDescriptor,
        layout = pipelineLayout,
        compute = cStruct(
            WGPUProgrammableStageDescriptor;
            _module = shader,
            entryPoint = toCString("main"),
        ) |> ptr |> unsafe_load,
    ) |> ptr,
)
## encoder
encoder = wgpuDeviceCreateCommandEncoder(
    device[],
    cStructPtr(
        WGPUCommandEncoderDescriptor;
        label = toCString("Command Encoder"),
    ),
)


## computePass
computePass = wgpuCommandEncoderBeginComputePass(
    encoder,
    cStructPtr(
        WGPUComputePassDescriptor;
        label = toCString("Compute Pass"),
    ),
)

## set pipeline
wgpuComputePassEncoderSetPipeline(computePass, computePipeline)
wgpuComputePassEncoderSetBindGroup(computePass, 0, bindGroup, 0, C_NULL)
wgpuComputePassEncoderDispatchWorkgroups(computePass, length(numbers), 1, 1)
wgpuComputePassEncoderEnd(computePass)

## buffer copy buffer
wgpuCommandEncoderCopyBufferToBuffer(
    encoder,
    storageBuffer,
    0,
    stagingBuffer,
    0,
    sizeof(numbers),
)

## queue
queue = wgpuDeviceGetQueue(device[])

## commandBuffer
cmdBuffer = wgpuCommandEncoderFinish(
    encoder,
    cStruct(WGPUCommandBufferDescriptor) |> ptr,
)

## writeBuffer
wgpuQueueWriteBuffer(queue, storageBuffer, 0, pointer(numbers), sizeof(numbers))

## submit queue
wgpuQueueSubmit(queue, 1, Ref(cmdBuffer))

## MapAsync
asyncstatus = Ref(WGPUBufferMapAsyncStatus(3))

function readBufferMap(status::WGPUBufferMapAsyncStatus, userData)
    asyncstatus[] = status
    return nothing
end

readbuffermap = @cfunction(readBufferMap, Cvoid, (WGPUBufferMapAsyncStatus, Ptr{Cvoid}))

wgpuBufferMapAsync(
    stagingBuffer,
    WGPUMapMode_Read,
    0,
    sizeof(numbers),
    readbuffermap,
    C_NULL,
)

print(asyncstatus[])

## device polling
wgpuDevicePoll(device[], true, C_NULL)

## times
times = convert(Ptr{UInt32}, wgpuBufferGetMappedRange(stagingBuffer, 0, sizeof(numbers)))

## result
for i = 1:length(numbers)
    println(numbers[i], " : ", unsafe_load(times, i))
end
