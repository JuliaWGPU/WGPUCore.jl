
mutable struct GPUBuffer <: Droppable
    label::Any
    internal::Any
    device::Any
    size::Any
    usage::Any
    desc::Any
end

asyncstatus = Ref(WGPUMapAsyncStatus(3))

function bufferCallback(status::WGPUMapAsyncStatus, userData)
    asyncstatus[] = status
    return nothing
end

function mapRead(gpuBuffer::GPUBuffer)
    bufferSize = gpuBuffer.size
    buffercallback =
        @cfunction(bufferCallback, Cvoid, (WGPUMapAsyncStatus, Ptr{Cvoid}))
    # Prepare
    data = convert(Ptr{UInt8}, Libc.malloc(bufferSize))

    buffercallbackInfo = WGPUBufferMapCallbackInfo |> CStruct
    buffercallbackInfo.callback = buffercallback

    wgpuBufferMapAsync(
        gpuBuffer.internal[],
        WGPUMapMode_Read,
        0,
        bufferSize,
        buffercallbackInfo |> concrete,
    )
    wgpuDevicePoll(gpuBuffer.device.internal[], true, C_NULL)

    if asyncstatus[] != WGPUMapAsyncStatus_Success
        @error "Couldn't read buffer data : $asyncstatus"
        asyncstatus[] = WGPUMapAsyncStatus(3)
    end

    asyncstatus[] = WGPUMapAsyncStatus(0)

    src_ptr =
        convert(Ptr{UInt8}, wgpuBufferGetMappedRange(gpuBuffer.internal[], 0, bufferSize))
	
    GC.@preserve src_ptr unsafe_copyto!(data, src_ptr, bufferSize)
    
    wgpuBufferUnmap(gpuBuffer.internal[])
    return unsafe_wrap(Array{UInt8, 1}, data, bufferSize)
end

function mapWrite(gpuBuffer::GPUBuffer, data)
    bufferSize = gpuBuffer.size
    @assert sizeof(data) == bufferSize
    buffercallback =
        @cfunction(bufferCallback, Cvoid, (WGPUMapAsyncStatus, Ptr{Cvoid}))

    buffercallbackInfo = WGPUBufferMapCallbackInfo |> CStruct
    buffercallbackInfo.callback = buffercallback

    wgpuBufferMapAsync(
        gpuBuffer.internal[],
        WGPUMapMode_Write,
        0,
        bufferSize,
        buffercallbackInfo |> concrete,
    )
    wgpuDevicePoll(gpuBuffer.device.internal, true)

    if asyncstatus[] != WGPUMapAsyncStatus_Success
        @error "Couldn't write buffer data: $asyncstatus"
        asyncstatus[] = WGPUMapAsyncStatus(3)
    end

    asyncstatus[] = WGPUMapAsyncStatus(0)

    src_ptr = wgpuBufferGetMappedRange(gpuBuffer.internal[], 0, bufferSize)
    src_ptr = convert(Ptr{UInt8}, src_ptr)
    dst_ptr = pointer(data)
    GC.@preserve src_ptr dst_ptr unsafe_copyto!(src_ptr, pointer(data), bufferSize)

    wgpuBufferUnmap(gpuBuffer.internal)
    return nothing
end

function createBuffer(label, gpuDevice, bufSize, usage, mappedAtCreation)
    labelPtr = toWGPUString(label)
    desc = cStruct(
        WGPUBufferDescriptor;
        label = labelPtr,
        size = bufSize,
        usage = getEnum(WGPUBufferUsage, usage),
        mappedAtCreation = mappedAtCreation,
    )
    buffer = wgpuDeviceCreateBuffer(
        gpuDevice.internal[],
        desc |> ptr,
    )
    GPUBuffer(label, buffer |> Ref, gpuDevice, bufSize, usage, desc)
end

function createBufferWithData(gpuDevice, label, data, usage)
    dataRef = data |> Ref #phantom reference
    bufSize = sizeof(data)
    buffer = createBuffer(label, gpuDevice, bufSize, usage, true)
    dstPtr = convert(Ptr{UInt8}, wgpuBufferGetMappedRange(buffer.internal[], 0, bufSize))
    GC.@preserve dstPtr begin
        dst = unsafe_wrap(Vector{UInt8}, dstPtr, bufSize)
        dst .= reinterpret(UInt8, data) |> flatten
    end
    wgpuBufferUnmap(buffer.internal[])
    return (buffer, dataRef, label)
end

## TODO
function computeWithBuffers(
    inputArrays::Dict{Int,Array},
    outputArrays::Dict{Int,Union{Int,Tuple}},
)

end

