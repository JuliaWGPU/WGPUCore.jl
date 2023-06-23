## Load WGPU
using WGPUCore
using WGPUCore: defaultInit
using WGPUCore: partialInit
using WGPUCore: pointerRef
using WGPUCore: toCString
using WGPUCore: SetLogLevel
using WGPUNative
## Constants
numbers = UInt32[1, 2, 3, 4]

const DEFAULT_ARRAY_SIZE = 256

SetLogLevel(WGPULogLevel_Debug)
## Init Window Size

const width = 200
const height = 200

println("Current Version : $(wgpuGetVersion())")

## 

adapter = Ref(WGPUAdapter())
device = Ref(WGPUDevice())

adapterOptions = cStruct(WGPURequestAdapterOptions) |> ptr

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

wgpuInstanceRequestAdapter(instance, adapterOptions, requestAdapterCallback, adapter)

wgpuAdapterRequestDevice(adapter[], C_NULL, requestDeviceCallback, device[])

## Buffer dimensions

struct BufferDimensions
    height::UInt32
    width::UInt32
    padded_bytes_per_row::UInt32
    unpadded_bytes_per_row::UInt32
    function BufferDimensions(width, height)
        bytes_per_pixel = sizeof(UInt32)
        unpadded_bytes_per_row = width * bytes_per_pixel
        align = 256
        padded_bytes_per_row_padding = (align - unpadded_bytes_per_row % align) % align
        padded_bytes_per_row = unpadded_bytes_per_row + padded_bytes_per_row_padding
        return new(height, width, padded_bytes_per_row, unpadded_bytes_per_row)
    end
end

bufferDimensions = BufferDimensions(width, height)


bufferSize = bufferDimensions.padded_bytes_per_row * bufferDimensions.height

outputBuffer = wgpuDeviceCreateBuffer(
    device[],
	cStruct(
	    WGPUBufferDescriptor;
	    nextInChain = C_NULL,
	    label = toCString("Output Buffer"),
	    usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst,
	    size = bufferSize,
	    mappedAtCreation = false,
    ) |> ptr
)

## textureExtent 

textureExtent = cStruct(
    WGPUExtent3D;
    width = bufferDimensions.width,
    height = bufferDimensions.height,
    depthOrArrayLayers = 1,
)

## texture

texture = wgpuDeviceCreateTexture(
    device[],
	cStruct(
	    WGPUTextureDescriptor;
	    nextInChain = C_NULL,
	    label = C_NULL,
	    size = textureExtent |> ptr |> unsafe_load,
	    mipLevelCount = 1,
	    sampleCount = 1,
	    dimension = WGPUTextureDimension_2D,
	    format = WGPUTextureFormat_RGBA8UnormSrgb,
	    usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc,
    ) |> ptr
)

## encoder

encoder = wgpuDeviceCreateCommandEncoder(
    device[],
    cStructPtr(WGPUCommandEncoderDescriptor),
)

## outputAttachment
# outputAttachment = wgpuTextureCreateView(
    # texture,
    # Ref(defaultInit(WGPUTextureViewDescriptor)),
# )
outputAttachment = wgpuTextureCreateView(
    texture,
    C_NULL,
)


## renderPass
renderPass = wgpuCommandEncoderBeginRenderPass(
    encoder,
    cStruct(
        WGPURenderPassDescriptor;
        colorAttachments = cStruct(
            WGPURenderPassColorAttachment;
            view = outputAttachment,
            resolveTarget = 0,
            loadOp = WGPULoadOp_Clear,
            storeOp = WGPUStoreOp_Store,
            clearValue = WGPUColor(1.0, 0.0, 0.0, 1.0),
        ) |> ptr,
        colorAttachmentCount = 1,
        depthStencilAttachment = C_NULL,
    ) |> ptr,
)




## end renderpass 
wgpuRenderPassEncoderEnd(renderPass)

## Copy texture to buffer

wgpuCommandEncoderCopyTextureToBuffer(
    encoder,
    cStruct(
        WGPUImageCopyTexture;
        texture = texture,
        mipLevel = 0,
        origin = WGPUOrigin3D(0, 0, 0),
    ) |> ptr,
    cStruct(
        WGPUImageCopyBuffer;
        buffer = outputBuffer,
        layout = cStruct(
            WGPUTextureDataLayout;
            offset = 0,
            bytesPerRow = bufferDimensions.padded_bytes_per_row,
            rowsPerImage = WGPU_COPY_STRIDE_UNDEFINED,
        ) |> ptr |> unsafe_load,
    ) |> ptr,
    textureExtent |> ptr,
)

## queue
queue = wgpuDeviceGetQueue(device[])

## commandBuffer
cmdBuffer = wgpuCommandEncoderFinish(
    encoder,
    cStruct(WGPUCommandBufferDescriptor) |> ptr,
)

## submit queue
wgpuQueueSubmit(queue, 1, Ref(cmdBuffer))

## MapAsync
asyncstatus = Ref(WGPUBufferMapAsyncStatus(3))

function readBufferMap(status::WGPUBufferMapAsyncStatus, userData)
    asyncstatus[] = status
    return nothing
end

readbuffermap = @cfunction(readBufferMap, Cvoid, (WGPUBufferMapAsyncStatus, Ptr{Cvoid}))

wgpuBufferMapAsync(outputBuffer, WGPUMapMode_Read, 0, bufferSize, readbuffermap, C_NULL)

print(asyncstatus[])

## device polling

wgpuDevicePoll(device[], true, C_NULL)

## times
times = convert(Ptr{UInt8}, wgpuBufferGetMappedRange(outputBuffer, 0, bufferSize))

## result
for i = 1:width*height
    println(i, " : ", unsafe_load(times, i))
end

## Unmap
wgpuBufferUnmap(outputBuffer)

## TODO dump as an image
