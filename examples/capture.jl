## Load WGPU
using WGPU

## Constants
numbers = UInt32[1,2,3,4]

const DEFAULT_ARRAY_SIZE = 256

## Init Window Size

const width = 200
const height = 200

println("Current Version : $(wgpuGetVersion())")

logcallback = @cfunction(logCallBack, Cvoid, (WGPULogLevel, Ptr{Cchar}))

wgpuSetLogCallback(logcallback)
wgpuSetLogLevel(WGPULogLevel(4))

## 

adapter = Ref(WGPUAdapter())
device = Ref(WGPUDevice())


adapterOptions = Ref(defaultInit(WGPURequestAdapterOptions))

function request_adapter_callback(
				a::WGPURequestAdapterStatus,
				b::WGPUAdapter,
			   c::Ptr{Cchar},
			   d::Ptr{Nothing})
    global adapter[] = b
	return nothing
end

requestAdapterCallback = @cfunction(request_adapter_callback, Cvoid, (WGPURequestAdapterStatus, WGPUAdapter, Ptr{Cchar}, Ptr{Cvoid}))

## device callback

function request_device_callback(
        a::WGPURequestDeviceStatus,
        b::WGPUDevice,
        c::Ptr{Cchar},
        d::Ptr{Nothing})
    global device[] = b
    return nothing
end

requestDeviceCallback = @cfunction(request_device_callback, Cvoid, (WGPURequestDeviceStatus, WGPUDevice, Ptr{Cchar}, Ptr{Cvoid}))


## request adapter 

wgpuInstanceRequestAdapter(C_NULL, 
						   adapterOptions, 
						   requestAdapterCallback,
						   adapter)

##

chain = WGPUChainedStruct(C_NULL, WGPUSType(6))

deviceName = Vector{UInt8}("Device")
deviceExtras = WGPUDeviceExtras(chain, defaultInit(WGPUNativeFeature), pointer(deviceName), C_NULL)

const DEFAULT_ARRAY_SIZE = 256

wgpuLimits = partialInit(WGPULimits; maxBindGroups = 1)

wgpuRequiredLimits = WGPURequiredLimits(C_NULL, wgpuLimits)

wgpuQueueDescriptor = WGPUQueueDescriptor(C_NULL, C_NULL)

wgpuDeviceDescriptor = Ref(
                        partialInit(
                            WGPUDeviceDescriptor,
                            nextInChain = pointer_from_objref(Ref(partialInit(WGPUChainedStruct, chain=deviceExtras))),
                            requiredLimits = pointer_from_objref(Ref(wgpuRequiredLimits)),
                            defaultQueue = wgpuQueueDescriptor
                        )
                      )


wgpuAdapterRequestDevice(
                 adapter[],
                 wgpuDeviceDescriptor,
                 requestDeviceCallback,
                 device[])

## Buffer dimensions

struct BufferDimensions
    height::UInt32
    width::UInt32
    padded_bytes_per_row::UInt32
    unpadded_bytes_per_row::UInt32
    function BufferDimensions(width, height)
        bytes_per_pixel = sizeof(UInt32)
        unpadded_bytes_per_row = width*bytes_per_pixel
        align = 256
        padded_bytes_per_row_padding = (align - unpadded_bytes_per_row % align) % align
        padded_bytes_per_row = unpadded_bytes_per_row + padded_bytes_per_row_padding
        return new(height, width, padded_bytes_per_row, unpadded_bytes_per_row)
    end
end

bufferDimensions = BufferDimensions(width, height)


bufferSize = bufferDimensions.padded_bytes_per_row*bufferDimensions.height

outputBuffer = wgpuDeviceCreateBuffer(
    device[],
    pointer_from_objref(Ref(partialInit(WGPUBufferDescriptor;
                nextInChain = C_NULL,
                label = pointer(Vector{UInt8}("Output Buffer")),
                usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst,
                size = bufferSize,
                mappedAtCreation = false
               )))
   )

## textureExtent 

textureExtent = partialInit(
    WGPUExtent3D;
    width = bufferDimensions.width,
    height = bufferDimensions.height,
    depthOrArrayLayers = 1
   )

## texture

texture = wgpuDeviceCreateTexture(
    device[],
    pointer_from_objref(Ref(partialInit(WGPUTextureDescriptor;
                                        nextInChain = C_NULL,
                                        lable = C_NULL,
                                        size = textureExtent,
                                        mipLevelCount = 1,
                                        sampleCount = 1,
                                        dimension = WGPUTextureDimension_2D,
                                        format = WGPUTextureFormat_RGBA8UnormSrgb,
                                        usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc,
                                       ))))

## encoder

encoder = wgpuDeviceCreateCommandEncoder(
               device[], 
               pointer_from_objref(Ref(defaultInit(WGPUCommandEncoderDescriptor))))

## outputAttachment
outputAttachment = wgpuTextureCreateView(
    texture,
    pointer_from_objref(Ref(defaultInit(WGPUTextureViewDescriptor)))
   )

           
## renderPass
renderPass = wgpuCommandEncoderBeginRenderPass(
    encoder,
    pointer_from_objref(Ref(partialInit(WGPURenderPassDescriptor;
        colorAttachments = pointer_from_objref(Ref(partialInit(WGPURenderPassColorAttachment;
                                                               view = outputAttachment,
                                                               resolveTarget = 0,
                                                               loadOp = WGPULoadOp_Clear,
                                                               storeOp = WGPUStoreOp_Store,
                                                               clearValue = WGPUColor(1.0, 0.0, 0.0, 1.0),
                                                              ))),
        colorAttachmentCount = 1,
        depthStencilAttachment = C_NULL
       )))
   )




## end renderpass 
wgpuRenderPassEncoderEnd(renderPass)

## Copy texture to buffer

wgpuCommandEncoderCopyTextureToBuffer(
    encoder,
    pointer_from_objref(Ref(partialInit(WGPUImageCopyTexture;
                                        texture = texture,
                                        miplevel = 0,
                                        origin = WGPUOrigin3D(0, 0, 0)))),
    pointer_from_objref(Ref(partialInit(WGPUImageCopyBuffer;
                                        buffer = outputBuffer,
                                        layout = partialInit(WGPUTextureDataLayout;
                                                             offset = 0,
                                                             bytesPerRow = bufferDimensions.padded_bytes_per_row,
                                                             rowsPerImage = 0
                                                            )))),
    Ref(textureExtent))

##


## 
#
#
#
#
##
#
#
#
##
#
#
#
#
##
#
#
#
#
## queue
queue = wgpuDeviceGetQueue(device[])

## commandBuffer
cmdBuffer = wgpuCommandEncoderFinish(
    encoder,
    pointer_from_objref(Ref(defaultInit(WGPUCommandBufferDescriptor)))
   )

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

wgpuBufferMapAsync(outputBuffer, WGPUMapMode_Read, 0, bufferSize, readbuffermap, C_NULL)

print(asyncstatus[])

## device polling

wgpuDevicePoll(device[], true)

## times
times = convert(Ptr{WGPUColor}, wgpuBufferGetMappedRange(outputBuffer, 0, bufferSize))

## result
for i in 1:width*height
    println(i, " : ", unsafe_load(times, i))
end




## Unmap
#
wgpuBufferUnmap(outputBuffer)

## TODO dump as an image






