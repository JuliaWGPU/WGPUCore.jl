module WGPUCore


using CEnum
##

include("utils.jl")

##
abstract type WGPUAbstractBackend end

##
function requestAdapter(::WGPUAbstractBackend, canvas, powerPreference)
    @error "Backend is not defined yet"
end

##
mutable struct GPUAdapter
    name::Any
    features::Any
    internal::Any
    limits::Any
    properties::Any
    options::Any
    supportedLimits::Any
    extras::Any
    backend::Any
end

##
mutable struct GPUDevice
    label::Any
    internal::Any
    adapter::Any
    features::Any
    queue::Any
    descriptor::Any
    requiredLimits::Any
    wgpuLimits::Any
    backend::Any
    supportedLimits::Any
end

##
mutable struct WGPUBackend <: WGPUAbstractBackend
    adapter::WGPURef{WGPUAdapter}
    device::WGPURef{WGPUDevice}
end

##
mutable struct GPUQueue
    label::Any
    internal::Any
    device::Any
end

##
mutable struct GPUBuffer
    label::Any
    internal::Any
    device::Any
    size::Any
    usage::Any
end

##
asyncstatus = Ref(WGPUBufferMapAsyncStatus(3))

##
function bufferCallback(status::WGPUBufferMapAsyncStatus, userData)
    asyncstatus[] = status
    return nothing
end

##
function mapRead(gpuBuffer::GPUBuffer)
    bufferSize = gpuBuffer.size
    buffercallback =
        @cfunction(bufferCallback, Cvoid, (WGPUBufferMapAsyncStatus, Ptr{Cvoid}))
    # Prepare
    data = convert(Ptr{UInt8}, Libc.malloc(bufferSize))
    wgpuBufferMapAsync(
        gpuBuffer.internal[],
        WGPUMapMode_Read,
        0,
        bufferSize,
        buffercallback,
        C_NULL,
    )
    wgpuDevicePoll(gpuBuffer.device.internal[], true, C_NULL)

    if asyncstatus[] != WGPUBufferMapAsyncStatus_Success
        @error "Couldn't read buffer data : $asyncstatus"
        asyncstatus[] = WGPUBufferMapAsyncStatus(3)
    end

    asyncstatus[] = WGPUBufferMapAsyncStatus(0)

    src_ptr =
        convert(Ptr{UInt8}, wgpuBufferGetMappedRange(gpuBuffer.internal[], 0, bufferSize))
	
    GC.@preserve src_ptr begin
        unsafe_copyto!(data, src_ptr, bufferSize)
    end
    wgpuBufferUnmap(gpuBuffer.internal[])
    return unsafe_wrap(Array{UInt8, 1}, data, bufferSize)
end

##
function mapWrite(gpuBuffer::GPUBuffer, data)
    bufferSize = gpuBuffer.size
    @assert sizeof(data) == bufferSize
    buffercallback =
        @cfunction(bufferCallback, Cvoid, (WGPUBufferMapAsyncStatus, Ptr{Cvoid}))

    wgpuBufferMapAsync(
        gpuBuffer.internal,
        WGPUMapMode_Write,
        0,
        bufferSize,
        buffercallback,
        C_NULL,
    )
    wgpuDevicePoll(gpuBuffer.device.internal, true)

    if asyncstatus[] != WGPUBufferMapAsyncStatus_Success
        @error "Couldn't write buffer data: $asyncstatus"
        asyncstatus[] = WGPUBufferMapAsyncStatus(3)
    end

    asyncstatus[] = WGPUBufferMapAsyncStatus(0)

    src_ptr = wgpuBufferGetMappedRange(gpuBuffer.internal[], 0, bufferSize)
    src_ptr = convert(Ptr{UInt8}, src_ptr)
    dst_ptr = pointer(data)
    GC.@preserve src_ptr dst_ptr begin
        unsafe_copyto!(src_ptr, pointer(data), bufferSize)
    end
    wgpuBufferUnmap(gpuBuffer.internal)
    return nothing
end

##
defaultInit(::Type{WGPUBackend}) = begin
    adapter = defaultInit(GPUAdapter)
    device = defaultInit(GPUDevice)
    return WGPUBackend(WGPURef(adapter), WGPURef(device))
end

##
function getAdapterCallback(adapter::WGPURef{WGPUAdapter})
    function request_adapter_callback(
        a::WGPURequestAdapterStatus,
        b::WGPUAdapter,
        c::Ptr{Cchar},
        d::Ptr{Nothing},
    )
        adapter[] = b
        return nothing
    end
    return request_adapter_callback
end

##
function getDeviceCallback(device::WGPURef{WGPUDevice})
    function request_device_callback(
        a::WGPURequestDeviceStatus,
        b::WGPUDevice,
        c::Ptr{Cchar},
        d::Ptr{Nothing},
    )
        device[] = b
        return nothing
    end
    return request_device_callback
end

##
adapter = WGPURef(defaultInit(WGPUAdapter))
device = WGPURef(defaultInit(WGPUDevice))
backend = WGPUBackend(adapter, device)

##
defaultInit(::Type{WGPUBackendType}) = WGPUBackendType_WebGPU

##
function requestAdapter(;
    canvas = nothing,
    powerPreference = defaultInit(WGPUPowerPreference),
)
    adapterExtras =
        cStructPtr(
            WGPUAdapterExtras;
            chain = cStruct(
                WGPUChainedStruct;
                sType = WGPUSType(Int64(WGPUSType_AdapterExtras)),
            ) |> ptr |> unsafe_load,
        )

    adapterOptions =
        cStruct(
            WGPURequestAdapterOptions;
            nextInChain = adapterExtras,
            powerPreference = powerPreference,
            forceFallbackAdapter = false,
        )

    requestAdapterCallback = @cfunction(
        getAdapterCallback(adapter),
        Cvoid,
        (WGPURequestAdapterStatus, WGPUAdapter, Ptr{Cchar}, Ptr{Cvoid})
    )

    # if adapter[] != C_NULL
        # tmpAdapter = adapter[]
        # adapter[] = C_NULL
        # destroy(tmpAdapter)
    # end

    wgpuInstanceRequestAdapter(
    	getWGPUInstance(), 
    	adapterOptions |> ptr, 
    	requestAdapterCallback, 
   		adapter[]
	)

    c_propertiesPtr = cStructPtr(WGPUAdapterProperties)

    wgpuAdapterGetProperties(adapter[], c_propertiesPtr)
    g = convert(Ptr{WGPUAdapterProperties}, c_propertiesPtr)
    h = GC.@preserve c_propertiesPtr unsafe_load(g)
    supportedLimitsPtr = cStructPtr(WGPUSupportedLimits;)
    GC.@preserve supportedLimitsPtr wgpuAdapterGetLimits(adapter[], supportedLimitsPtr)
    h = GC.@preserve supportedLimitsPtr unsafe_load(supportedLimitsPtr)
    features = []
    partialInit(
        GPUAdapter;
        name = "WGPU",
        features = features,
        internal = adapter,
        limits = h.limits,
        properties = c_propertiesPtr,
        options = adapterOptions,
        supportedLimits = supportedLimitsPtr,
        extras = adapterExtras,
    )
end

##
function requestDevice(
    gpuAdapter::GPUAdapter;
    label = " DEVICE DESCRIPTOR ",
    requiredFeatures = [],
    requiredLimits = [],
    defaultQueue = [],
    tracepath = "",
)
    # TODO trace path
    # Drop devices TODO
    # global backend
    chainObj = cStruct(
        WGPUChainedStruct;
        next = C_NULL,
        sType = WGPUSType(Int32(WGPUSType_DeviceExtras)),
    )

    deviceExtras = cStruct(
        WGPUDeviceExtras;
        chain = chainObj |> ptr |> unsafe_load,
        tracePath = toCString(tracepath),
    )

    wgpuLimits = cStruct(WGPULimits; maxBindGroups = 2) # TODO set limits
    wgpuRequiredLimits =
        cStruct(WGPURequiredLimits; nextInChain = C_NULL, limits = wgpuLimits |> concrete)

    wgpuQueueDescriptor = cStruct(
        WGPUQueueDescriptor;
        nextInChain = C_NULL,
        label = toCString("DEFAULT QUEUE"),
    ) 

    wgpuDeviceDescriptor =
        cStruct(
            WGPUDeviceDescriptor;
            label = toCString(label),
            nextInChain = convert(Ptr{WGPUChainedStruct}, deviceExtras |> ptr),
            requiredFeaturesCount = 0,
            requiredLimits = (wgpuRequiredLimits |> ptr),
            defaultQueue = wgpuQueueDescriptor |> ptr |> unsafe_load,
        )

    requestDeviceCallback = @cfunction(
        getDeviceCallback(device),
        Cvoid,
        (WGPURequestDeviceStatus, WGPUDevice, Ptr{Cchar}, Ptr{Cvoid})
    )
    # TODO dump all the info to a string or add it to the GPUAdapter structure
    if device[] == C_NULL
        wgpuAdapterRequestDevice(
            gpuAdapter.internal[],
            C_NULL,
            requestDeviceCallback,
            device[],
        )
    end

    supportedLimits = cStruct(WGPUSupportedLimits;)

    supportedLimitsPtr = supportedLimits |> ptr
    wgpuDeviceGetLimits(device[], supportedLimitsPtr)
    g = convert(Ptr{WGPUSupportedLimits}, supportedLimitsPtr)
    h = GC.@preserve supportedLimitsPtr unsafe_load(g)
    features = []
    deviceQueue = WGPURef(wgpuDeviceGetQueue(device[]))
    queue = GPUQueue(" GPU QUEUE ", deviceQueue, nothing)
    # GPUDevice("WGPU", backend.device, backend.adapter, features, h.limits, queue, wgpuQueueDescriptor, wgpuRequiredLimits, wgpuLimits)
    partialInit(
        GPUDevice;
        label = "WGPU Device",
        internal = device,
        adapter = gpuAdapter,
        features = features,
        limits = h.limits,
        queue = queue,
        descriptor = wgpuQueueDescriptor,
        requiredLimits = wgpuRequiredLimits,
        supportedLimits = supportedLimits,
    )
end

function createBuffer(label, gpuDevice, bufSize, usage, mappedAtCreation)
    labelPtr = toCString(label)
    buffer = GC.@preserve labelPtr wgpuDeviceCreateBuffer(
        gpuDevice.internal[],
        cStruct(
            WGPUBufferDescriptor;
            label = labelPtr,
            size = bufSize,
            usage = getEnum(WGPUBufferUsage, usage),
            mappedAtCreation = mappedAtCreation,
        ) |> ptr,
    ) |> WGPURef
    GPUBuffer(label, buffer, gpuDevice, bufSize, usage)
end

function getDefaultDevice(; backend = backend)
    adapter = WGPUCore.requestAdapter()
    defaultDevice = requestDevice(adapter[])
    return defaultDevice
end

flatten(x) = reshape(x, (:,))

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

## 
mutable struct GPUTexture
    label::Any
    internal::Any
    device::Any
    texInfo::Any
end

## BufferDimension
mutable struct BufferDimensions
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

function createTexture(
    gpuDevice,
    label,
    size,
    mipLevelCount,
    sampleCount,
    dimension,
    format,
    usage,
)
    textureExtent =
        cStruct(
            WGPUExtent3D;
            width = size[1],
            height = size[2],
            depthOrArrayLayers = size[3],
        )
    texture = GC.@preserve label wgpuDeviceCreateTexture(
        gpuDevice.internal[],
        cStruct(
            WGPUTextureDescriptor;
            label = toCString(label),
            size = textureExtent |> concrete,
            mipLevelCount = mipLevelCount,
            sampleCount = sampleCount,
            dimension = dimension,
            format = format,
            usage = usage,
        ) |> ptr,
    ) |> Ref

    texInfo = Dict(
        "size" => size,
        "mipLevelCount" => mipLevelCount,
        "sampleCount" => sampleCount,
        "dimension" => dimension,
        "format" => format,
        "usage" => usage,
    )

    GPUTexture(label, texture, gpuDevice, texInfo)
end

##
mutable struct GPUTextureView
    label::Any
    internal::Any
    device::Any
    texture::Any
    size::Any
    desc::Any
end
##
function createView(gpuTexture::GPUTexture; dimension = nothing)
    gpuTextureInternal = gpuTexture.internal[]
    dimension = split(string(gpuTexture.texInfo["dimension"]), "_")[end]
    T = WGPUTextureViewDimension
    pairs = CEnum.name_value_pairs(T)
    for (key, value) in pairs
        pattern = split(string(key), "_")[end] # TODO MallocInfo
        if pattern == dimension # TODO partial matching will be good but tie break will happen
            dimension = T(value)
        end
    end
    texSize = gpuTexture.texInfo["size"]
    viewDescriptor =
        cStruct(
            WGPUTextureViewDescriptor;
            label = toCString(gpuTexture.label),
            format = gpuTexture.texInfo["format"],
            dimension = dimension,
            aspect = WGPUTextureAspect_All,
            baseMipLevel = 0, # TODO
            mipLevelCount = 1, # TODO
            baseArrayLayer = 0, # TODO
            arrayLayerCount = last(texSize),  # TODO
        ) |> ptr
    view = GC.@preserve gpuTextureInternal wgpuTextureCreateView(
        gpuTexture.internal[],
        viewDescriptor,
    ) |> Ref
    return GPUTextureView(
        gpuTexture.label,
        view,
        gpuTexture.device,
        gpuTexture |> Ref,
        gpuTexture.texInfo["size"],
        viewDescriptor,
    )
end

## Sampler Bits
mutable struct GPUSampler
    label::Any
    internal::Any
    device::Any
end

function createSampler(
    gpuDevice;
    label = " SAMPLER DESCRIPTOR",
    addressModeU = WGPUAddressMode_ClampToEdge,
    addressModeV = WGPUAddressMode_ClampToEdge,
    addressModeW = WGPUAddressMode_ClampToEdge,
    magFilter = WGPUFilterMode_Nearest,
    minFilter = WGPUFilterMode_Nearest,
    mipmapFilter = WGPUMipmapFilterMode_Nearest,
    lodMinClamp = 0,
    lodMaxClamp = 32,
    compare = WGPUCompareFunction_Undefined,
    maxAnisotropy = 1,
)
    sampler =
        wgpuDeviceCreateSampler(
            gpuDevice.internal[],
            cStruct(
                WGPUSamplerDescriptor;
                label = toCString(label),
                addressModeU = addressModeU,
                addressModeV = addressModeV,
                addressModeW = addressModeW,
                magFilter = magFilter,
                minFilter = minFilter,
                mipmapFilter = mipmapFilter,
                lodMinClamp = lodMinClamp,
                lodMaxClamp = lodMaxClamp,
                compare = compare == nothing ? 0 : compare,
                maxAnisotropy = maxAnisotropy,
            ) |> ptr,
        ) |> Ref
    return GPUSampler(label, sampler, gpuDevice)
end

mutable struct GPUBindGroupLayout
    label::Any
    internal::Any
    device::Any
    bindings::Any
    desc::Any
end

abstract type WGPUEntryType end

struct WGPUBufferEntry <: WGPUEntryType end

struct WGPUSamplerEntry <: WGPUEntryType end

struct WGPUTextureEntry <: WGPUEntryType end

struct WGPUStorageTextureEntry <: WGPUEntryType end

function createLayoutEntry(::Type{WGPUBufferEntry}; args...)
    # binding::Int,
    # visibility::Int,
    # buffertype::WGPUBufferBindingType)
    bufferBindingLayout = cStruct(
        WGPUBufferBindingLayout;
        type = getEnum(WGPUBufferBindingType, args[:type]),
    )
    entry =cStruct(
        WGPUBindGroupLayoutEntry;
        binding = args[:binding],
        visibility = getEnum(WGPUShaderStage, args[:visibility]),
        buffer = bufferBindingLayout |> concrete,
    )
    return (entry, bufferBindingLayout)
end

function createLayoutEntry(::Type{WGPUSamplerEntry}; args...)
    # binding::Int,
    # visibility::Int,
    # sampertype::WGPUBufferBindingType
    samplerBindingLayout = cStruct(
        WGPUSamplerBindingLayout;
        type = getEnum(WGPUSamplerBindingType, args[:type]),
    )
    entry = cStruct(
        WGPUBindGroupLayoutEntry;
        binding = args[:binding],
        visibility = getEnum(WGPUShaderStage, args[:visibility]),
        sampler = samplerBindingLayout |> concrete,
    )
    return (entry, samplerBindingLayout)
end

function createLayoutEntry(::Type{WGPUTextureEntry}; args...)
    # binding::UInt32 = 0,
    # visibility::UInt32 = 0,
    # type::WGPUTextureSampleType = WGPUTextureSampleType_Float,
    # viewDimension::WGPUTextureViewDimension = WGPUTextureViewDimension_2D,
    # multisampled::Bool=false
	textureBindingLayout = cStruct(
        WGPUTextureBindingLayout;
        sampleType = getEnum(WGPUTextureSampleType, args[:sampleType]),
        viewDimension = getEnum(WGPUTextureViewDimension, args[:viewDimension]),
        multisampled = args[:multisampled],
    )
    entry = cStruct(
        WGPUBindGroupLayoutEntry;
        binding = args[:binding],
        visibility = getEnum(WGPUShaderStage, args[:visibility]),
        texture = textureBindingLayout |> concrete,
    )
    return (entry, textureBindingLayout)
end

function createLayoutEntry(::Type{WGPUStorageTextureEntry}; args...)
    # binding,
    # visibility,
    # access::WGPUStorageTextureAccess,
    # format::WGPUTextureFormat;
    # viewDimension::WGPUTextureViewDimension=WGPUTextureViewDimension_2D
    storageTextureBindingLayout = cStruct(
        WGPUStorageTextureBindingLayout;
        access = getEnum(WGPUStorageTextureAccess, args[:access]),
        viewDimension = getEnum(WGPUTextureViewDimension, args[:viewDimension]),
        format = getEnum(WGPUTextureFormat, args[:format]),
    ),

    entry = cStruct(
        WGPUBindGroupLayoutEntry;
        binding = args[:binding],
        visibility = getEnum(WGPUShaderStage, args[:visibility]),
        storageTexture = storageTextureBindingLayout |> concrete
    )
    return (entry, storageTextureBindingLayout)
end

function createBindGroupEntry(::Type{GPUBuffer}; args...)
    cStruct(
        WGPUBindGroupEntry;
        binding = args[:binding],
        buffer = args[:buffer].internal[],
        offset = args[:offset],
        size = args[:size],
        sampler = C_NULL,
        textureView = C_NULL,
    )
end

function createBindGroupEntry(::Type{GPUTextureView}; args...)
    cStruct(
        WGPUBindGroupEntry;
        binding = args[:binding],
        textureView = args[:textureView].internal[],
    )
end

function createBindGroupEntry(::Type{GPUSampler}; args...)
    cStruct(
        WGPUBindGroupEntry;
        binding = args[:binding],
        sampler = args[:sampler].internal[],
    )
end

function makeLayoutEntryList(entries)
    @assert typeof(entries) <: Array "Entries should be an array"
    entryLen = length(entries)
    cEntries = convert(
    	Ptr{WGPUBindGroupLayoutEntry},
    	Libc.malloc(sizeof(WGPUBindGroupLayoutEntry)*entryLen)
   	)
    if entryLen > 0
        for (idx, entry) in enumerate(entries)
        	entryCntxt = createLayoutEntry(entry.first; entry.second...)
            unsafe_store!(cEntries, entryCntxt |> first |> concrete, idx)
        end
    end
    return unsafe_wrap(Array, cEntries, entryLen; own=false)
end

function createBindGroupLayout(gpuDevice, label, entries)
    @assert typeof(entries) <: Array "Entries should be an array"
    count = length(entries)
    bindGroupLayout = C_NULL
    bindGroupLayoutDesc = nothing
    if count > 0
		bindGroupLayoutDesc = cStruct(
	       WGPUBindGroupLayoutDescriptor;
	       label = toCString(label),
	       entries = count == 0 ? C_NULL : entries |> pointer, # assuming array of entries
	       entryCount = count,
	   	)

        bindGroupLayout = GC.@preserve label wgpuDeviceCreateBindGroupLayout(
            gpuDevice.internal[],
		 	bindGroupLayoutDesc |> ptr,
        )
    end
    GPUBindGroupLayout(label, Ref(bindGroupLayout), gpuDevice, entries, bindGroupLayoutDesc)
end

mutable struct GPUBindGroup
    label::Any
    internal::Any
    layout::Any
    device::Any
    bindings::Any
    desc::Any
end

function makeBindGroupEntryList(entries)
    @assert typeof(entries) <: Array "Entries should be an array"
    entriesLen = length(entries)
    cEntries = convert(
    	Ptr{WGPUBindGroupEntry},
    	Libc.malloc(sizeof(WGPUBindGroupEntry)*entriesLen)
    )
    if entriesLen > 0
        for (idx, entry) in enumerate(entries)
        	entryCntxt = createBindGroupEntry(entry.first; entry.second...)
            unsafe_store!(cEntries, entryCntxt |> concrete, idx)
        end
    end
    return unsafe_wrap(Array, cEntries, entriesLen; own=false)
end

function createBindGroup(label, gpuDevice, bindingLayout, entries)
    @assert typeof(entries) <: Array "Entries should be an array"
    count = length(entries)
    bindGroup = C_NULL
    bindGroupDesc = nothing
    if bindingLayout.internal[] != C_NULL && count > 0
        bindGroupDesc = cStruct(
	        WGPUBindGroupDescriptor;
	        label = toCString(label),
	        layout = bindingLayout.internal[],
	        entries = count == 0 ? C_NULL : entries |> pointer,
	        entryCount = count,
	    )
        bindGroup = GC.@preserve label wgpuDeviceCreateBindGroup(
            gpuDevice.internal[],
			bindGroupDesc |> ptr
        )
    end
    GPUBindGroup(label, Ref(bindGroup), bindingLayout, gpuDevice, entries, bindGroupDesc)
end

function makeBindGroupAndLayout(gpuDevice, bindingLayouts, bindings)
    @assert length(bindings) == length(bindingLayouts)
    cBindingLayoutsList = makeLayoutEntryList(bindingLayouts)
    cBindingsList = makeBindGroupEntryList(bindings)
    bindGroupLayout =
        createBindGroupLayout(gpuDevice, "Bind Group Layout", cBindingLayoutsList)
    bindGroup = createBindGroup("BindGroup", gpuDevice, bindGroupLayout, cBindingsList)
    return (bindGroupLayout, bindGroup)
end

mutable struct GPUPipelineLayout
    label::Any
    internal::Any
    device::Any
    layouts::Any
    descriptor::Any
end

function createPipelineLayout(gpuDevice, label, bindGroupLayoutObj)
    # bindGroupLayoutArray = Ptr{WGPUBindGroupLayoutImpl}()
    # if bindGroupLayoutObj.internal[] != C_NULL
        # bindGroupLayoutArray = bindGroupLayoutObj.internal[]
        # layoutCount = length(bindGroupLayoutArray)
    # else
    	# layoutCount = 0
    # end
    bindGroupLayoutArray = []
    if bindGroupLayoutObj.internal[] != C_NULL
        bindGroupLayoutArray = map((x) -> x.internal[], [bindGroupLayoutObj])
        layoutCount = length(bindGroupLayoutArray) # will always be one
    else
    	layoutCount = 0
    end 
    pipelineDescriptor = GC.@preserve bindGroupLayoutArray label cStruct(
        WGPUPipelineLayoutDescriptor;
        label = toCString(label),
        bindGroupLayouts = layoutCount == 0 ? C_NULL : bindGroupLayoutArray |> pointer,
        bindGroupLayoutCount = layoutCount,
    )
    pipelineLayout =
        wgpuDeviceCreatePipelineLayout(gpuDevice.internal[], pipelineDescriptor |> ptr) |> Ref
    GPUPipelineLayout(
        label,
        pipelineLayout,
        gpuDevice,
        bindGroupLayoutObj,
        pipelineDescriptor,
    )
end

mutable struct GPUShaderModule
    label::Any
    internal::Any
    device::Any
end

function loadWGSL(buffer::Vector{UInt8}; name = " UnnamedShader ")
   	chain = cStruct(
   		WGPUChainedStruct;
   		next = C_NULL,
   		sType = WGPUSType_ShaderModuleWGSLDescriptor
	) |> ptr |> unsafe_load
    wgslDescriptor = cStruct(
    	WGPUShaderModuleWGSLDescriptor;
		chain = chain,
    	code = pointer(buffer)
    )
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr ,
        label = toCString(name),
    )
    return (a, buffer, chain, wgslDescriptor, names)
end

function loadWGSL(buffer::IOBuffer; name = " UnknownShader ")
    b = read(buffer)
   	chain = cStruct(
   		WGPUChainedStruct;
   		next = C_NULL,
   		sType = WGPUSType_ShaderModuleWGSLDescriptor
	) |> ptr |> unsafe_load
    wgslDescriptor = cStruct(
    	WGPUShaderModuleWGSLDescriptor;
		chain = chain,
    	code = pointer(b)
    )
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr,
        label = toCString(name),
    )
    return (a, b, chain, wgslDescriptor, names)
end

function loadWGSL(file::IOStream; name = " UnknownShader ")
    b = read(file)
   	chain = cStruct(
   		WGPUChainedStruct;
   		next = C_NULL,
   		sType = WGPUSType_ShaderModuleWGSLDescriptor
	) |> ptr |> unsafe_load
    wgslDescriptor = cStruct(
    	WGPUShaderModuleWGSLDescriptor;
		chain = chain,
    	code = pointer(b)
    )
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr,
        label = toCString(name == "UnknownShader" ? file.name : name),
    )
    return (a, b, chain, wgslDescriptor, name)
end

function createShaderModule(gpuDevice, label, shadercode, sourceMap, hints)
    shader = GC.@preserve shadercode wgpuDeviceCreateShaderModule(
        gpuDevice.internal[],
        shadercode |> ptr,
    ) |> Ref

    GPUShaderModule(label, shader, gpuDevice)
end

mutable struct GPUComputePipeline
    label::Any
    internal::Any
    device::Any
    layout::Any
    desc::Any
end

mutable struct ComputeStage
    internal::Any
    entryPoint::Any
end

function createComputeStage(shaderModule, entryPoint::String)
    computeStage = cStruct(
        WGPUProgrammableStageDescriptor;
        _module = shaderModule.internal[],
        entryPoint = toCString(entryPoint),
    )
    return ComputeStage(computeStage, entryPoint)
end

function createComputePipeline(gpuDevice, label, pipelinelayout, computeStage)
	desc =	cStruct(
        WGPUComputePipelineDescriptor;
        label = toCString(label),
        layout = pipelinelayout.internal[],
        compute = computeStage.internal |> concrete,
    )
    computepipeline = GC.@preserve label wgpuDeviceCreateComputePipeline(
        gpuDevice.internal[],
        desc |> ptr,
    ) |> Ref
    GPUComputePipeline(label, computepipeline, gpuDevice, pipelinelayout, desc)
end

mutable struct GPUVertexAttribute
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUVertexAttribute}; args...)
    GPUVertexAttribute(
        cStruct(
            WGPUVertexAttribute;
            format = getEnum(WGPUVertexFormat, args[:format]),
            offset = args[:offset],
            shaderLocation = args[:shaderLocation],
        ),
        args,
    )
end

mutable struct GPUVertexBufferLayout
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUVertexBufferLayout}; args...)
    attributeArgs = args[:attributes]
	numAttrs = length(attributeArgs)
    attributeArrayPtr = convert(
    	Ptr{WGPUVertexAttribute},
    	Libc.malloc(sizeof(WGPUVertexAttribute)*numAttrs)
    )
    attributeObjs = GPUVertexAttribute[]

    for (idx, attribute) in enumerate(attributeArgs)
        obj = createEntry(GPUVertexAttribute; attribute.second...)
        push!(attributeObjs, obj)
        unsafe_store!(attributeArrayPtr, obj.internal |> concrete, idx)
    end

    aref = GC.@preserve attributeArrayPtr cStruct(
        WGPUVertexBufferLayout;
        arrayStride = args[:arrayStride],
        stepMode = getEnum(WGPUVertexStepMode, args[:stepMode]),
        attributes = attributeArrayPtr,
        attributeCount = numAttrs,
        xref1 = attributeArrayPtr |> Ref,
    )
    return GPUVertexBufferLayout(aref, (attributeArgs, args, attributeArrayPtr |> Ref, attributeObjs .|> Ref))
end

mutable struct GPUVertexState
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUVertexState}; args...)
    buffers = args[:buffers]
	bufferLen = length(buffers)
	
    bufferDescArrayPtr = convert(
    	Ptr{WGPUVertexBufferLayout},
    	Libc.malloc(sizeof(WGPUVertexBufferLayout)*bufferLen)
    )
    
    buffersArrayObjs = GPUVertexBufferLayout[] |> Ref
    entryPointArg = args[:entryPoint]

    for (idx, buffer) in enumerate(buffers)
        obj = createEntry(buffer.first; buffer.second...)
        push!(buffersArrayObjs[], obj )
        unsafe_store!(bufferDescArrayPtr, obj.internal |> concrete, idx)
    end

    shader = args[:_module]
    if shader != C_NULL
        shaderInternal = shader.internal
    else
        shaderInternal = C_NULL |> Ref
    end

    aRef = GC.@preserve entryPointArg bufferDescArrayPtr cStruct(
        WGPUVertexState;
        _module = shaderInternal[],
        entryPoint = toCString(entryPointArg),
        buffers = length(buffers) == 0 ? C_NULL : bufferDescArrayPtr,
        bufferCount = length(buffers),
        xref1 = bufferDescArrayPtr,
        xref2 = shader,
    ) |> Ref
    GPUVertexState(aRef, (shader, buffers, bufferDescArrayPtr, buffersArrayObjs .|> Ref, entryPointArg, args))
end

mutable struct GPUPrimitiveState
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUPrimitiveState}; args...)
    a = cStruct(
        WGPUPrimitiveState;
        topology = getEnum(WGPUPrimitiveTopology, args[:topology]),
        stripIndexFormat = getEnum(WGPUIndexFormat, args[:stripIndexFormat]),
        frontFace = getEnum(WGPUFrontFace, args[:frontFace]), # TODO 
        cullMode = getEnum(WGPUCullMode, args[:cullMode]),
    ) |> Ref
    return GPUPrimitiveState(a, args)
end

mutable struct GPUStencilFaceState
    internal::Any
    strongRefs::Any
end


defaultInit(::Type{WGPUStencilFaceState}) = begin
    cStruct(WGPUStencilFaceState; compare = WGPUCompareFunction_Always)
end

mutable struct GPUDepthStencilState
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUDepthStencilState}; args...)
    aref = nothing
    if length(args) > 0 && args != C_NULL
        aref =
            cStruct(
                WGPUDepthStencilState;
                format = args[:format],
                depthWriteEnabled = args[:depthWriteEnabled],
                depthCompare = args[:depthCompare],
                stencilReadMask = get(args, :stencilReadMask, 0xffffffff),
                stencilWriteMask = get(args, :stencilWriteMask, 0xffffffff),
            ) |> Ref
    else
        aref = C_NULL |> Ref
    end
    return GPUDepthStencilState(aref, args |> Ref)
end

mutable struct GPUMultiSampleState
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUMultiSampleState}; args...)
    a =
        cStruct(
            WGPUMultisampleState;
            count = args[:count],
            mask = args[:mask],
            alphaToCoverageEnabled = args[:alphaToCoverageEnabled],
        ) |> Ref
    return GPUMultiSampleState(a, args)
end

mutable struct GPUBlendComponent
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUBlendComponent}; args...)
    a = cStruct(
        WGPUBlendComponent;
        srcFactor = getEnum(WGPUBlendFactor, args[:srcFactor]),
        dstFactor = getEnum(WGPUBlendFactor, args[:dstFactor]),
        operation = getEnum(WGPUBlendOperation, args[:operation]),
    )
    return GPUBlendComponent(a, args)
end

mutable struct GPUBlendState
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUBlendState}; args...)
    a = cStruct(WGPUBlendState; color = args[:color], alpha = args[:alpha])
    return GPUBlendState(a, args)
end

mutable struct GPUColorTargetState
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUColorTargetState}; args...)
    kargs = Dict(args)
    colorEntry = createEntry(GPUBlendComponent; args[:color]...)
    alphaEntry = createEntry(GPUBlendComponent; args[:alpha]...)
    # blendArgs = [:color => colorEntry |> concrete, :alpha => alphaEntry |> concrete]
    blend = CStruct(WGPUBlendState)
    blend.color = colorEntry.internal |> concrete
    blend.alpha = alphaEntry.internal |> concrete
    kargs[:writeMask] = get(kargs, :writeMask, WGPUColorWriteMask_All)
    aref = GC.@preserve args blend cStruct(
        WGPUColorTargetState;
        format = kargs[:format],
        blend = blend |> ptr,
        writeMask = kargs[:writeMask],
    ) |> Ref
    return GPUColorTargetState(
        aref,
        (blend, blend, colorEntry, alphaEntry, args, kargs),
    )
end

mutable struct GPUFragmentState
    internal::Any
    strongRefs::Any
end

function createEntry(::Type{GPUFragmentState}; args...)
    targetsArg = args[:targets]
    targetsLen = length(targetsArg)
    ctargets = convert(
    	Ptr{WGPUColorTargetState},
    	Libc.malloc(sizeof(WGPUColorTargetState)*targetsLen)
    )
    targetObjs = GPUColorTargetState[]

    for (idx, target) in enumerate(targetsArg)
        obj = createEntry(target.first; target.second...)
        push!(targetObjs, obj)
        unsafe_store!(ctargets, obj.internal[] |> concrete, idx)
    end

    entryPointArg = args[:entryPoint]
    shader = args[:_module]
    shaderInternal = shader.internal
    aref = GC.@preserve entryPointArg ctargets shaderInternal cStruct(
        WGPUFragmentState;
        _module = shaderInternal[],
        entryPoint = toCString(entryPointArg),
        targets = ctargets,
        targetCount = targetsLen,
    ) |> Ref
    return GPUFragmentState(
        aref,
        (
            aref,
            args,
            shader,
            entryPointArg |> Ref,
            targetsArg,
            ctargets |> Ref,
            targetObjs |> Ref,
            entryPointArg,
            shaderInternal,
        ),
    )
end

mutable struct GPURenderPipeline
    label::Any
    internal::Any
    descriptor::Any
    renderArgs::Any
    device::Any
    layout::Any
    vertexState::Any
    primitiveState::Any
    depthStencilState::Any
    MultiSampleState::Any
    FragmentState::Any
end

function createRenderPipeline(
    gpuDevice,
    pipelinelayout,
    renderpipeline;
    label = "RenderPipeLine",
)
    renderArgs = Dict()
    for state in renderpipeline
        obj = createEntry(state.first; state.second...)
        @info obj
        renderArgs[state.first] = obj.internal
    end

    vertexState = renderArgs[GPUVertexState]
    primitiveState = renderArgs[GPUPrimitiveState]
    depthStencilState = renderArgs[GPUDepthStencilState]
    multiSampleState = renderArgs[GPUMultiSampleState]
    fragmentState = renderArgs[GPUFragmentState]

    pipelineDesc = GC.@preserve label cStruct(
        WGPURenderPipelineDescriptor;
        label = toCString(label),
        layout = pipelinelayout.internal[],
        vertex = vertexState[] |> concrete,
        primitive = primitiveState[] |> concrete,
        depthStencil = let ds = depthStencilState[]
        	 ds == C_NULL ? C_NULL : ds |> ptr 
      	end,
        multisample = multiSampleState[] |> concrete,
        fragment = fragmentState[] |> ptr,
    )

    renderpipeline = GC.@preserve pipelineDesc wgpuDeviceCreateRenderPipeline(
        gpuDevice.internal[],
        pipelineDesc |> ptr,
    ) |> Ref

    return GPURenderPipeline(
        label,
        renderpipeline,
        pipelineDesc |> Ref,
        renderArgs,
        gpuDevice,
        pipelinelayout |> Ref,
        vertexState |> Ref,
        primitiveState |> Ref,
        depthStencilState |> Ref,
        multiSampleState |> Ref,
        fragmentState |> Ref,
    )
end

mutable struct GPUColorAttachments
    internal::Any
    strongRefs::Any
end

mutable struct GPUColorAttachment
    internal::Any
    strongRefs::Any
end


mutable struct GPUDepthStencilAttachments
    internal::Any
    strongRefs::Any
end

mutable struct GPUDepthStencilAttachment
    internal::Any
    strongRefs::Any
end

mutable struct GPURenderPassEncoder
    label::Any
    internal::Any
    pipeline::Any
    cmdEncoder::Any
    desc::Any
    renderArgs::Any
end

function createEntry(::Type{GPUColorAttachment}; args...)
    textureView = args[:view]
    a = cStruct(
        WGPURenderPassColorAttachment;
        view = textureView.internal[],
        resolveTarget = args[:resolveTarget],
        clearValue = WGPUColor(args[:clearValue]...),
        loadOp = args[:loadOp],
        storeOp = args[:storeOp],
    )
    return GPUColorAttachment(a, (args, textureView) .|> Ref)
end


function createEntry(::Type{GPUColorAttachments}; args...)
    attachments = WGPURenderPassColorAttachment[]
    attachmentObjs = GPUColorAttachment[]
    for attachment in get(args, :attachments, [])
        obj = createEntry(attachment.first; attachment.second...) # TODO MallocInfo
        push!(attachmentObjs, obj)
        push!(attachments, obj.internal |> concrete)
    end
    return GPUColorAttachments(attachments |> Ref, (attachments, attachmentObjs) .|> Ref)
end


function createEntry(::Type{GPUDepthStencilAttachment}; args...)
    depthview = args[:view]
    a = GC.@preserve depthview cStruct(
        WGPURenderPassDepthStencilAttachment;
        view = depthview.internal[],
        depthClearValue = args[:depthClearValue],
        depthLoadOp = args[:depthLoadOp],
        depthStoreOp = args[:depthStoreOp],
        stencilLoadOp = get(args, :stencilLoadOp, WGPULoadOp_Clear),
        stencilStoreOp = get(args, :stencilStoreOp, WGPUStoreOp_Store),
    ) |> Ref
    return GPUDepthStencilAttachment(a, (args, depthview) .|> Ref)
end


function createEntry(::Type{GPUDepthStencilAttachments}; args...)
    attachments = WGPURenderPassDepthStencilAttachment[]
    attachmentObjs = GPUDepthStencilAttachment[]
    for attachment in get(args, :attachments, [])
        obj = createEntry(attachment.first; attachment.second...) # TODO MallocInfo
        push!(attachmentObjs, obj)
        push!(attachments, obj.internal[] |> concrete)
    end
    return GPUDepthStencilAttachments(
        attachments |> Ref,
        (attachments, attachmentObjs) .|> Ref,
    )
end

mutable struct GPUCommandBuffer
    label::Any
    internal::Any
    device::Any
end


function createCommandBuffer()

end


mutable struct GPUCommandEncoder
    label::Any
    internal::Any
    device::Any
    desc::Any
end


mutable struct GPUComputePassEncoder
    label::Any
    internal::Any
    cmdEncoder::Any
    desc::Any
end


function createCommandEncoder(gpuDevice, label)
    cmdEncDesc = GC.@preserve label cStruct(
        WGPUCommandEncoderDescriptor;
        label = toCString(label),
    ) |> ptr
    commandEncoder =
        wgpuDeviceCreateCommandEncoder(
            gpuDevice.internal[],
            cmdEncDesc,
        ) |> Ref
    return GPUCommandEncoder(label, commandEncoder, gpuDevice, cmdEncDesc)
end

function beginComputePass(
    cmdEncoder::GPUCommandEncoder;
    label = " COMPUTE PASS DESCRIPTOR ",
    timestampWrites = [],
)
    desc =
        GC.@preserve label cStruct(
        	WGPUComputePassDescriptor; label = toCString(label)
       	) |> ptr
    computePass = wgpuCommandEncoderBeginComputePass(cmdEncoder.internal[], desc) |> Ref
    GPUComputePassEncoder(label, computePass, cmdEncoder, desc)
end

function beginRenderPass(
    cmdEncoder::GPUCommandEncoder,
    renderPipelinePairs;
    label = " BEGIN RENDER PASS ",
)
    renderArgs = Dict() # MallocInfo
    for config in renderPipelinePairs[]
        renderArgs[config.first] = createEntry(config.first; config.second...)
    end
    # Both color and depth attachments requires pointer
    colorAttachmentsIn = renderArgs[GPUColorAttachments]
    depthStencilAttachmentIn = renderArgs[GPUDepthStencilAttachments]
    desc = GC.@preserve label cStruct(
        WGPURenderPassDescriptor;
        label = toCString(label),
        colorAttachments = let ca = colorAttachmentsIn
            length(ca.internal[]) > 0 ? pointer(ca.internal[]) : C_NULL
        end,
        colorAttachmentCount = length(colorAttachmentsIn.internal[]),
        depthStencilAttachment = let da = depthStencilAttachmentIn
            length(da.internal[]) > 0 ? pointer(da.internal[]) : C_NULL
        end,
    ) |> ptr
    renderPass = wgpuCommandEncoderBeginRenderPass(cmdEncoder.internal[], desc) |> WGPURef
    GPURenderPassEncoder(
        label,
        renderPass,
        renderPipelinePairs,
        cmdEncoder,
        desc,
        renderArgs |> Ref,
    )
end

function copyBufferToBuffer(
    cmdEncoder::GPUCommandEncoder,
    source::GPUBuffer,
    sourceOffset::Int,
    destination::GPUBuffer,
    destinationOffset::Int,
    size::Int,
)
    @assert sourceOffset % 4 == 0 "Source offset must be multiple of 4"
    @assert destinationOffset % 4 == 0 "Destination offset must be a multiple of 4"
    @assert size % 4 == 0 "Size must be a multiple of 4"

    wgpuCommandEncoderCopyBufferToBuffer(
        cmdEncoder.internal[],
        source.internal[],
        sourceOffset,
        destination.internal[],
        destinationOffset,
        size,
    )
end

function copyBufferToTexture(
    cmdEncoder::GPUCommandEncoder,
    source::Dict{Symbol,Any},
    destination::Dict{Symbol,Any},
    copySize::Dict{Symbol,Int64},
)
    rowAlignment = 256
    bytesPerRow = source[:layout][:bytesPerRow]
    @assert bytesPerRow % rowAlignment == 0 "BytesPerRow must be multiple of $rowAlignment"
    origin = get(source, :origin, [:x => 0, :y => 0, :z => 0] |> Dict)
    cOrigin = cStruct(WGPUOrigin3D; origin...)
    cDestination =
        cStruct(
            WGPUImageCopyTexture;
            texture = source[:texture].internal[],
            mipLevel = get(source, :mipLevel, 0),
            origin = cOrigin,
            aspect = getEnum(WGPUTextureAspect, "All"),
        ) |> ptr
    cSource =
        cStruct(
            WGPUImageCopyBuffer;
            buffer = destination[:buffer].internal[],
            layout = cStruct(WGPUTextureDataLayout; destination[:layout]...),
        ) |> ptr
  
    cCopySize = cStruct(WGPUExtent3D; copy...) |> ptr

    wgpuCommandEncoderCopyBufferToTexture(
        cmdEncoder.internal[],
        cSource,
        cDestination,
        cCopySize,
    )
end

function copyTextureToBuffer(
    cmdEncoder::GPUCommandEncoder,
    source::Dict{Symbol,Any},
    destination::Dict{Symbol,Any},
    copySize::Dict{Symbol,Int64},
)
    rowAlignment = 256
    dest = Dict(destination)
    bytesPerRow = dest[:layout][:bytesPerRow]
    @assert bytesPerRow % rowAlignment == 0 "BytesPerRow must be multiple of $rowAlignment"
    origin = get(source, :origin, [:x => 0, :y => 0, :z => 0] |> Dict)
    cOrigin = cStruct(WGPUOrigin3D; origin...)
    cSource =
        cStruct(
            WGPUImageCopyTexture;
            texture = source[:texture].internal[],
            mipLevel = get(source, :mipLevel, 0),
            origin = cOrigin |> concrete,
            aspect = getEnum(WGPUTextureAspect, "All"),
        ) |> ptr
    cDestination =
        cStruct(
            WGPUImageCopyBuffer;
            buffer = destination[:buffer].internal[],
            layout = cStruct(
                WGPUTextureDataLayout;
                destination[:layout]..., # should document these obscure
            ) |> concrete,
        ) |> ptr
    cCopySize = cStruct(WGPUExtent3D; copySize...) |> ptr

    wgpuCommandEncoderCopyTextureToBuffer(
        cmdEncoder.internal[],
        cSource,
        cDestination,
        cCopySize,
    )
end

function copyTextureToTexture(
    cmdEncoder::GPUCommandEncoder,
    source::Dict{Symbol,Any},
    destination::Dict{Symbol,Any},
    copySize::Dict{Symbol,Int64},
)
    origin1 = get(source, :origin, [:x => 0, :y => 0, :z => 0])
    cOrigin1 = cStruct(WGPUOrigin3D; origin1...) |> concrete

    cSource =
        cStruct(
            WGPUImageCopyTexture;
            texture = source[:texture].internal[],
            mipLevel = get(source, :mipLevel, 0),
            origin = COrigin1,
        ) |> ptr

    origin2 = get(destination, :origin, [:x => 0, :y => 0, :z => 0])

    cOrigin2 = cStruct(WGPUOrigin3D; origin2...) |> concrete

    cDestination =
        cStruct(
            WGPUImageCopyTexture;
            texture = destination[:texture].internal[],
            mipLevel = get(destination, :mipLevel, 0),
            origin = cOrigin2,
        ) |> ptr

    cCopySize = cStruct(WGPUExtent3D; copySize...) |> ptr

    wgpuCommandEncoderCopyTextureToTexture(
        cmdEncoder.internal[],
        cSource,
        cDestination,
        cCopySize,
    )

end

function finish(cmdEncoder::GPUCommandEncoder; label = " CMD ENCODER COMMAND BUFFER ")
    cmdEncoderFinish = wgpuCommandEncoderFinish(
        cmdEncoder.internal[],
        cStruct(WGPUCommandBufferDescriptor; label = toCString(label)) |> ptr,
    )
    cmdEncoder.internal[] = C_NULL # Just to avoid 'Cannot remove a vacant resource'
    return GPUCommandBuffer(label, Ref(cmdEncoderFinish), cmdEncoder)
end


function createRenderBundleEncoder()

end


function createComputePassEncoder()

end


function createRenderPassEncoder()

end

function setPipeline(computePass::GPUComputePassEncoder, pipeline)
    wgpuComputePassEncoderSetPipeline(computePass.internal[], pipeline.internal[])
end

function setBindGroup(
    computePass::GPUComputePassEncoder,
    index::Int,
    bindGroup::GPUBindGroup,
    dynamicOffsetsData::Vector{UInt32},
    start::Int,
    dataLength::Int,
)
    offsetcount = length(dynamicOffsetsData)
    setbindgroup = wgpuComputePassEncoderSetBindGroup(
        computePass.internal[],
        index,
        bindGroup.internal[],
        offsetcount,
        (offsetcount == 0) ? C_NULL : pointer(dynamicOffsetsData),
    )
    return nothing
end

function setBindGroup(
    renderPass::GPURenderPassEncoder,
    index::Int,
    bindGroup::GPUBindGroup,
    dynamicOffsetsData::Vector{UInt32},
    start::Int,
    dataLength::Int,
)
    offsetcount = length(dynamicOffsetsData)
    setbindgroup = wgpuRenderPassEncoderSetBindGroup(
        renderPass.internal[],
        index,
        bindGroup.internal[],
        offsetcount,
        offsetcount == 0 ? C_NULL : pointer(dynamicOffsetsData),
    )
    return nothing
end

function dispatchWorkGroups(
    computePass::GPUComputePassEncoder,
    countX,
    countY = 1,
    countZ = 1,
)
    wgpuComputePassEncoderDispatchWorkgroups(computePass.internal[], countX, countY, countZ)
end

function dispatchWorkGroupsIndirect(
    computePass::GPUComputePassEncoder,
    indirectBuffer,
    indirectOffset,
)
    bufferId = indirectBuffer.internal[]
    wgpuComputePassEncoderDispatchIndirect(computePass.internal[], bufferId, indirectOffset)
end


function endComputePass(computePass::GPUComputePassEncoder)
    wgpuComputePassEncoderEnd(computePass.internal[])
end

function setViewport(
    renderPass::GPURenderPassEncoder,
    x,
    y,
    width,
    height,
    minDepth,
    maxDepth,
)
    wgpuRenderPassEncoderSetViewport(
        renderPass.internal[],
        float(x),
        float(y),
        float(width),
        float(height),
        float(minDepth),
        float(maxDepth),
    )
end

function setScissorRect(renderPass::GPURenderPassEncoder, x, y, width, height)
    wgpuRenderPassEncoderSetScissorRect(
        renderPass.internal[],
        int.([x, y, width, height])...,
    )
end

function setPipeline(
    renderPassEncoder::GPURenderPassEncoder,
    renderpipeline::GPURenderPipeline,
)
    wgpuRenderPassEncoderSetPipeline(
        renderPassEncoder.internal[],
        renderpipeline.internal[],
    )
end

function setIndexBuffer(
    rpe::GPURenderPassEncoder,
    buffer,
    indexFormat;
    offset = 0,
    size = nothing,
)
    if size == nothing
        size = buffer.size - offset
    end
    cIndexFormat = getEnum(WGPUIndexFormat, indexFormat)
    wgpuRenderPassEncoderSetIndexBuffer(
        rpe.internal[],
        buffer.internal[],
        cIndexFormat,
        offset,
        size,
    )
end

function setVertexBuffer(
    rpe::GPURenderPassEncoder,
    slot,
    buffer,
    offset = 0,
    size = nothing,
)
    if size == nothing
        size = buffer.size - offset
    end
    wgpuRenderPassEncoderSetVertexBuffer(
        rpe.internal[],
        slot,
        buffer.internal[],
        offset,
        size,
    )
end

function draw(
    renderPassEncoder::GPURenderPassEncoder,
    vertexCount;
    instanceCount = 1,
    firstVertex = 0,
    firstInstance = 0,
)
    wgpuRenderPassEncoderDraw(
        renderPassEncoder.internal[],
        vertexCount,
        instanceCount,
        firstVertex,
        firstInstance,
    )
end

function drawIndexed(
    renderPassEncoder::GPURenderPassEncoder,
    indexCount;
    instanceCount = 1,
    firstIndex = 0,
    baseVertex = 0,
    firstInstance = 0,
)
    wgpuRenderPassEncoderDrawIndexed(
        renderPassEncoder.internal[],
        indexCount,
        instanceCount,
        firstIndex,
        baseVertex,
        firstInstance,
    )
end

function endEncoder(renderPass::GPURenderPassEncoder)
    wgpuRenderPassEncoderEnd(renderPass.internal[])
end

function submit(queue::GPUQueue, commandBuffers)
    commandBufferListPtr = map((cmdbuf) -> cmdbuf.internal[], commandBuffers)
    GC.@preserve commandBufferListPtr wgpuQueueSubmit(
        queue.internal[],
        length(commandBuffers),
        commandBufferListPtr |> pointer,
    )
    for cmdbuf in commandBuffers
        cmdbuf.internal[] = C_NULL
    end
end

function writeTexture(queue::GPUQueue; args...)
    args = Dict(args)
    dst = args[:dst]
    for i in dst
        @eval $(i.first) = $(i.second)
    end

    cOrigin = WGPUOrigin3D(origin...) |> Ref

    destination =
        cStruct(
            WGPUImageCopyTexture;
            texture = texture[].internal[],
            mipLevel = mipLevel,
            origin = cOrigin[],
        ) 

    layout = args[:layout]
    for i in layout
        @eval $(i.first) = $(i.second)
    end
    cDataLayout =
        cStruct(
            WGPUTextureDataLayout;
            offset = offset,
            bytesPerRow = bytesPerRow,
            rowsPerImage = rowsPerImage,
        )
    texSize = args[:textureSize]
    size =
        cStruct(
            WGPUExtent3D;
            width = texSize[1],
            height = texSize[2],
            depthOrArrayLayers = texSize[3],
        ) 
    texData = args[:textureData]
    texDataPtr = pointer(texData[])
    dataLength = length(texData[])
    GC.@preserve texDataPtr wgpuQueueWriteTexture(
        queue.internal[],
        destination |> ptr,
        texDataPtr,
        dataLength,
        cDataLayout |> ptr,
        size |> ptr,
    )
end

function readTexture()
    # TODO
end

function readBuffer(gpuDevice, buffer, bufferOffset, size)
    # TODO more implementation is required
    # Took shortcut
    usage = ["CopyDst", "MapRead"]
    tmpBuffer = WGPUCore.createBuffer(" READ BUFFER TEMP ", gpuDevice, size, usage, false)
    commandEncoder = createCommandEncoder(gpuDevice, " READ BUFFER COMMAND ENCODER ")
    copyBufferToBuffer(commandEncoder, buffer, bufferOffset, tmpBuffer, 0, size)
    submit(gpuDevice.queue, [finish(commandEncoder)])
    data = mapRead(tmpBuffer)
    destroy(tmpBuffer)
    return data
end

function writeBuffer(queue::GPUQueue, buffer, data; dataOffset = 0, size = nothing)
    # TODO checks
    wgpuQueueWriteBuffer(queue.internal[], buffer.internal[], 0, data, sizeof(data))
end

forceOffscreen = false

if forceOffscreen == true
    include("offscreen.jl")
elseif Sys.isapple()
    include("metalglfw.jl")
elseif Sys.islinux()
    include("glfw.jl")
elseif Sys.iswindows()
    include("glfw.jl") # TODO windows is not tested yet
end

function destroy(texView::GPUTextureView)
    if texView.internal[] != C_NULL
        tmpTex = texView.internal[]
        texView.internal[] = C_NULL
        wgpuTextureViewDrop(tmpTex)
    end
end

function Base.setproperty!(texview::GPUTextureView, s::Symbol, value)
    if s == :internal && texview.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(texview)
        end
    end
end

function destroy(tex::GPUTexture)
    if tex.internal[] != C_NULL
        tmpTex = tex.internal[]
        tex.internal[] = C_NULL
        wgpuTextureDrop(tmpTex)
    end
end

function Base.setproperty!(tex::GPUTexture, s::Symbol, value)
    if s == :internal && tex.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(tex)
        end
    end
end

function destroy(sampler::GPUSampler)
    if sampler.internal[] != C_NULL
        tmpSampler = sampler.internal[]
        sampler.internal[] = C_NULL
        wgpuSamplerDrop(tmpSampler)
    end
end

function Base.setproperty!(sampler::GPUSampler, s::Symbol, value)
    if s == :internal && sampler.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(sampler)
        end
    end
end

function destroy(layout::GPUBindGroupLayout)
    if layout.internal[] != C_NULL
        tmpLayout = layout.internal[]
        layout.internal[] = C_NULL
        wgpuBindGroupLayoutDrop(tmpLayout)
    end
end

function Base.setproperty!(layout::GPUBindGroupLayout, s::Symbol, value)
    if s == :internal && layout.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(layout)
        end
    end
end

function destroy(bindGroup::GPUBindGroup)
    if bindGroup.internal[] != C_NULL
        tmpBindGroup = bindGroup.internal[]
        bindGroup.internal[] = C_NULL
        wgpuBindGroupDrop(tmpBindGroup)
    end
end

function Base.setproperty!(bindGroup::GPUBindGroup, s::Symbol, value)
    if s == :internal && bindGroup.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(bindGroup)
        end
    end
end

function destroy(layout::GPUPipelineLayout)
    if layout.internal[] != C_NULL
        tmpLayout = layout.internal[]
        layout.internal[] = C_NULL
        wgpuPipelineLayoutDrop(tmpLayout)
    end
end

function Base.setproperty!(pipeline::GPUPipelineLayout, s::Symbol, value)
    if s == :internal && pipeline.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(pipeline)
        end
    end
end

function destroy(shader::GPUShaderModule)
    if shader.internal[] != C_NULL
        tmpShader = shader.internal[]
        shader.internal[] = C_NULL
        wgpuShaderModuleDrop(tmpShader)
    end
end

function Base.setproperty!(shader::GPUShaderModule, s::Symbol, value)
    if s == :internal && shader.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(shader)
        end
    end
end

function destroy(pipeline::GPUComputePipeline)
    if pipeline.internal[] != C_NULL
        tmpPipeline = pipeline.internal[]
        pipeline.internal[] = C_NULL
        wgpuComputePipelineDrop(tmpPipeline)
    end
end

function Base.setproperty!(pipeline::GPUComputePipeline, s::Symbol, value)
    if s == :internal && pipeline.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(pipeline)
        end
    end
end

function destroy(pipeline::GPURenderPipeline)
    if pipeline.internal[] != C_NULL
        tmpPipeline = pipeline.internal[]
        pipeline.internal[] = C_NULL
        wgpuRenderPipelineDrop(tmpPipeline)
    end
end

function Base.setproperty!(pipeline::GPURenderPipeline, s::Symbol, value)
    if s == :internal && pipeline.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(pipeline)
        end
    end
end

function destroy(gpuBuffer::GPUBuffer)
    if gpuBuffer.internal[] != C_NULL
        tmpBufferPtr = gpuBuffer.internal[]
        gpuBuffer.internal[] = C_NULL
        wgpuBufferDrop(tmpBufferPtr)
    end
end

function Base.setproperty!(buf::GPUBuffer, s::Symbol, value)
    if s == :internal && buf.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(buf)
        end
    end
end

function destroy(cmdBuffer::GPUCommandBuffer)
    if cmdBuffer.internal[] != C_NULL
        tmpCmdBufferPtr = cmdBuffer.internal[]
        cmdBuffer.internal[] = C_NULL
        wgpuCommandBufferDrop(tmpCmdBufferPtr)
    end
end

function Base.setproperty!(buf::GPUCommandBuffer, s::Symbol, value)
    if s == :internal && buf.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(buf)
        end
    end
end

function destroy(cmdEncoder::GPUCommandEncoder)
    if cmdEncoder.internal[] != C_NULL
        tmpCmdEncoderPtr = cmdEncoder.internal[]
        cmdEncoder.internal[] = C_NULL
        wgpuCommandEncoderDrop(tmpCmdEncoderPtr)
    end
end

function Base.setproperty!(enc::GPUCommandEncoder, s::Symbol, value)
    if s == :internal && enc.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(enc)
        end
    end
end

function destroy(adapter::GPUAdapter)
    if adapter.internal[] != C_NULL
        tmpAdapterPtr = adapter.internal[]
        adapter.internal = nothing
        adapter = nothing
    end
end

function destroy(adapter::Ptr{WGPUAdapterImpl})
    if adapter != C_NULL
        tmpAdapterPtr = adapter
        adapter = C_NULL
    end
end

function Base.setproperty!(adapter::GPUAdapter, s::Symbol, value)
    if s == :internal && adapter.internal[] != C_NULL
        if value == nothing || value == C_NULL
            destroy(adapter)
        end
    end
end

function destroy(device::GPUDevice)
    if device.internal[] != C_NULL
        tmpDevicePtr = device.internal[]
        device.internal[] = C_NULL
        wgpuDeviceDrop(tmpDevicePtr)
    end
end

function Base.setproperty!(device::GPUDevice, s::Symbol, value)
    if s == :internal && device.internal[] != C_NULL
        if value == nothing || value == C_NULL
            sleep(1)
            destroy(device)
        end
    end
end

# TODO 
function isdestroyable()
	
end

end
