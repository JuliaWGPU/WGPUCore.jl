
module WGPU

using CEnum
using GLFW
##

DEBUG=false

function setDebugMode(mode)
	global DEBUG
	DEBUG=mode
end

include("utils.jl")

##
abstract type WGPUAbstractBackend end

##
function requestAdapter(::WGPUAbstractBackend, canvas, powerPreference)
    @error "Backend is not defined yet"
end

##
mutable struct GPUAdapter
    name
    features
    internal
    limits
    properties
    options
    supportedLimits
    extras
    backend
end

##
mutable struct GPUDevice
    label
    internal
    adapter
    features
    queue
    descriptor
    requiredLimits
    wgpuLimits
    backend
    supportedLimits
end

##
mutable struct WGPUBackend <: WGPUAbstractBackend
    adapter::WGPURef{WGPUAdapter}
    device::WGPURef{WGPUDevice}
end

##
mutable struct GPUQueue
    label
    internal
    device
end

##
mutable struct GPUBuffer
	label
	internal
	device
	size
	usage
end

##
asyncstatus = Ref(WGPUBufferMapAsyncStatus(3))

##
function bufferCallback(
	status::WGPUBufferMapAsyncStatus,
	userData
)
	asyncstatus[] = status
	return nothing
end

##
function mapRead(gpuBuffer::GPUBuffer)
	bufferSize = gpuBuffer.size
	buffercallback = @cfunction(bufferCallback, Cvoid, (WGPUBufferMapAsyncStatus, Ptr{Cvoid}))
	# Prepare
	data = Vector{UInt8}(undef, bufferSize)
	wgpuBufferMapAsync(gpuBuffer.internal[], WGPUMapMode_Read, 0, bufferSize, buffercallback, C_NULL)
	wgpuDevicePoll(gpuBuffer.device.internal[], true)

	if asyncstatus[] != WGPUBufferMapAsyncStatus_Success
		@error "Couldn't read buffer data : $asyncstatus"
		asyncstatus[] = WGPUBufferMapAsyncStatus(3)
	end
	
	asyncstatus[] = WGPUBufferMapAsyncStatus(0)

	src_ptr = convert(Ptr{UInt8}, wgpuBufferGetMappedRange(gpuBuffer.internal[], 0, bufferSize))
	GC.@preserve src_ptr begin
		src = unsafe_wrap(Vector{UInt8}, src_ptr, bufferSize; own=false)
		data .= src
	end
	wgpuBufferUnmap(gpuBuffer.internal[])
	return data
end

##
function mapWrite(gpuBuffer::GPUBuffer, data)
	bufferSize = gpuBuffer.size
	@assert sizeof(data) == bufferSize
	buffercallback = @cfunction(bufferCallback, Cvoid, (WGPUBufferMapAsyncStatus, Ptr{Cvoid}))

	wgpuBufferMapAsync(gpuBuffer.internal, WGPUMapMode_Write, 0, bufferSize, buffercallback, C_NULL)
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
            d::Ptr{Nothing})
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
            d::Ptr{Nothing})
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
function requestAdapter(; canvas=nothing, powerPreference = defaultInit(WGPUPowerPreference))
    adapterExtras = partialInit(
    	WGPUAdapterExtras;
    	chain = partialInit(
    		WGPUChainedStruct;
			sType = WGPUSType(Int64(WGPUSType_AdapterExtras))
		)
	) |> Ref

    adapterOptions = partialInit(
    	WGPURequestAdapterOptions;
		nextInChain=C_NULL,
		powerPreference=powerPreference,
		forceFallbackAdapter=false
	) |> Ref
	
    requestAdapterCallback = @cfunction(
    	getAdapterCallback(adapter),
   		Cvoid,
   		(WGPURequestAdapterStatus, WGPUAdapter, Ptr{Cchar}, Ptr{Cvoid})
   	)
   	
   	if adapter[] != C_NULL
   		tmpAdapter = adapter[]
   		adapter[] = C_NULL
   		destroy(tmpAdapter)
   	end
   	
    wgpuInstanceRequestAdapter(
    	C_NULL,
        adapterOptions,
        requestAdapterCallback,
        adapter[]
    )

    c_properties = partialInit(
    	WGPUAdapterProperties
   	) 
   	
   	c_propertiesPtr = c_properties |> pointer_from_objref

    wgpuAdapterGetProperties(adapter[], c_propertiesPtr)
    g = convert(Ptr{WGPUAdapterProperties}, c_propertiesPtr)
    h = GC.@preserve c_propertiesPtr unsafe_load(g)
    supportedLimits = partialInit(
    	WGPUSupportedLimits;
   	) 
    supportedLimitsPtr = supportedLimits |> pointer_from_objref
    GC.@preserve supportedLimitsPtr wgpuAdapterGetLimits(adapter[], supportedLimitsPtr)
    g = convert(Ptr{WGPUSupportedLimits}, supportedLimitsPtr)
    h = GC.@preserve supportedLimits unsafe_load(g)
    features = []
    partialInit(
		GPUAdapter;
   	    name = "WGPU",
   	    features = features,
   	    internal = adapter,
   	    limits = h.limits,
   	    properties = c_properties,
   	    options = adapterOptions,
   	    supportedLimits = supportedLimits,
   	    extras = adapterExtras
    )
end

##
function requestDevice(gpuAdapter::GPUAdapter;
		label = " DEVICE DESCRIPTOR ", 
        requiredFeatures=[], 
        requiredLimits=[],
        defaultQueue=[],
        tracepath = " ")
    # TODO trace path
    # Drop devices TODO
    # global backend
    chain = partialInit(
    	WGPUChainedStruct;
    	mext = C_NULL, 
    	sType = WGPUSType(Int32(WGPUSType_DeviceExtras))
   	)
   	
    deviceName = pointer("Device") |> WGPURef
    
    deviceExtras = partialInit(
    	WGPUDeviceExtras;
    	chain = chain[], 
    	nativeFeatures = defaultInit(WGPUNativeFeature), 
    	label = deviceName[], 
    	tracePath = pointer(tracepath)
   	)
   	
    wgpuLimits = partialInit(WGPULimits; maxBindGroups = 2) # TODO set limits
    wgpuRequiredLimits = partialInit(
   		WGPURequiredLimits; 
		nextInChain = C_NULL,
		limits = wgpuLimits[],
	)
	
    wgpuQueueDescriptor = partialInit(
    	WGPUQueueDescriptor;
    	nextInChain = C_NULL, 
    	label = pointer("DEFAULT QUEUE")
   	)
   	
    wgpuDeviceDescriptor = partialInit(
	        WGPUDeviceDescriptor;
	        label = pointer(label),
	        nextInChain = partialInit(
	        	WGPUChainedStruct;
                chain=deviceExtras[]
            ) |> pointer_from_objref,
	        requiredFeaturesCount=0,
	        requiredLimits = pointer_from_objref(wgpuRequiredLimits),
	        defaultQueue = wgpuQueueDescriptor[]
		) |> pointer_from_objref
	
    requestDeviceCallback = @cfunction(getDeviceCallback(device), Cvoid, (WGPURequestDeviceStatus, WGPUDevice, Ptr{Cchar}, Ptr{Cvoid}))
    # TODO dump all the info to a string or add it to the GPUAdapter structure
    if device[] == C_NULL
	    wgpuAdapterRequestDevice(
	                gpuAdapter.internal[],
	                wgpuDeviceDescriptor,
	                requestDeviceCallback,
	                device[]
	               )
	end

    supportedLimits = partialInit(
    	WGPUSupportedLimits;
   	)
   	
   	supportedLimitsPtr  = supportedLimits |> pointer_from_objref
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
	    supportedLimits = supportedLimits
    )
end

function createBuffer(label, gpuDevice, bufSize, usage, mappedAtCreation)
	labelPtr = pointer(label)
    buffer = GC.@preserve labelPtr wgpuDeviceCreateBuffer(
    	gpuDevice.internal[],
    	partialInit(WGPUBufferDescriptor;
			label = labelPtr,
			size = bufSize,
			usage = getEnum(WGPUBufferUsage, usage),
			mappedAtCreation = mappedAtCreation
    	) |> pointer_from_objref
    ) |> WGPURef
    GPUBuffer(label, buffer, gpuDevice, bufSize, usage)
end

function getDefaultDevice(;backend=backend)
	adapter = WGPU.requestAdapter()
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
	inputArrays::Dict{Int, Array},
	outputArrays::Dict{Int, Union{Int, Tuple}}
)
	
end

## 
mutable struct GPUTexture
	label
	internal
	device
	texInfo
end

## BufferDimension
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

function createTexture(gpuDevice, 
						label,
						size, 
						mipLevelCount, 
						sampleCount, 
						dimension, 
						format, 
						usage)
	textureExtent = partialInit(
		WGPUExtent3D;
		width = size[1],
		height = size[2],
		depthOrArrayLayers = size[3]
	) |> Ref
	labelPtr = pointer(label)
	texture = GC.@preserve labelPtr wgpuDeviceCreateTexture(
		gpuDevice.internal[],
		partialInit(
			WGPUTextureDescriptor;
			label = labelPtr,
			size = textureExtent[],
			mipLevelCount = mipLevelCount,
			sampleCount = sampleCount,
			dimension = dimension,
			format = format,
			usage = usage
		) |> Ref
	) |> Ref

	texInfo = Dict(
		"size" => size,
		"mipLevelCount" => mipLevelCount,
		"sampleCount" => sampleCount,
		"dimension" => dimension,
		"format" => format,
		"usage" => usage
	)

	GPUTexture(label, texture, gpuDevice, texInfo)
end

##
mutable struct GPUTextureView
	label
	internal
	device
	texture
	size
end
##
function createView(gpuTexture::GPUTexture; dimension=nothing)
	dimension = split(string(gpuTexture.texInfo["dimension"]), "_")[end]
	T = WGPUTextureViewDimension
	pairs = CEnum.name_value_pairs(T)
	for (key, value) in pairs
		pattern = split(string(key), "_")[end]
		if pattern == dimension # TODO partial matching will be good but tie break will happen
			dimension = T(value)
		end
	end
	viewDescriptor = partialInit(
		WGPUTextureViewDescriptor;
		label = pointer(gpuTexture.label),
		format = gpuTexture.texInfo["format"],
		dimension = dimension,
		aspect = WGPUTextureAspect_All,
		baseMipLevel = 0, # TODO
		mipLevelCount = 1, # TODO
		baseArrayLayer = 0, # TODO
		arrayLayerCount = 1  # TODO
	) |> Ref
	internal = wgpuTextureCreateView(gpuTexture.internal[], viewDescriptor) |> Ref
	return GPUTextureView(
		gpuTexture.label,
		internal,
		gpuTexture.device,
		gpuTexture,
		gpuTexture.texInfo["size"]
	)
end

## Sampler Bits
mutable struct GPUSampler
	label
	internal
	device
end

function createSampler(gpuDevice;
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
				maxAnisotropy = 1)
	sampler = wgpuDeviceCreateSampler(
				gpuDevice.internal[],
				partialInit(
					WGPUSamplerDescriptor;
					label = pointer(label),
					addressModeU = addressModeU,
					addressModeV = addressModeV,
					addressModeW = addressModeW,
					magFilter = magFilter,
					minFilter = minFilter,
					mipmapFilter = mipmapFilter,
					lodMinClamp = lodMinClamp,
					lodMaxClamp = lodMaxClamp,
					compare = compare == nothing ? 0 : compare,
					maxAnisotropy = maxAnisotropy
				) |> Ref
			) |> Ref
	return GPUSampler(label, sampler, gpuDevice)
end

mutable struct GPUBindGroupLayout
	label
	internal
	device
	bindings
end

abstract type WGPUEntryType end

struct WGPUBufferEntry <: WGPUEntryType end

struct WGPUSamplerEntry <: WGPUEntryType end

struct WGPUTextureEntry <: WGPUEntryType end

struct WGPUStorageTextureEntry <: WGPUEntryType end

function createEntry(::Type{WGPUBufferEntry}; args...)
	# binding::Int,
	# visibility::Int,
	# buffertype::WGPUBufferBindingType)
	partialInit(
		WGPUBindGroupLayoutEntry;
		binding = args[:binding], 
		visibility = getEnum(WGPUShaderStage, args[:visibility]),
		buffer = partialInit(
			WGPUBufferBindingLayout;
			type = getEnum(WGPUBufferBindingType, args[:type]),
		)
	)
end

function createEntry(::Type{WGPUSamplerEntry}; args...)
	# binding::Int,
	# visibility::Int,
	# sampertype::WGPUBufferBindingType
	partialInit(
		WGPUBindGroupLayoutEntry;
		binding= args[:binding], 
		visibility=getEnum(WGPUShaderStage, args[:visibility]),
		sampler = partialInit(
			WGPUSamplerBindingLayout;
			type = getEnum(WGPUSamplerBindingType, args[:type]),
		),
	)
end

function createEntry(::Type{WGPUTextureEntry}; args...)
	# binding::UInt32 = 0,
	# visibility::UInt32 = 0,
	# type::WGPUTextureSampleType = WGPUTextureSampleType_Float,
	# viewDimension::WGPUTextureViewDimension = WGPUTextureViewDimension_2D,
	# multisampled::Bool=false
	partialInit(
		WGPUBindGroupLayoutEntry;
		binding = args[:binding], 
		visibility=getEnum(WGPUShaderStage, args[:visibility]),
		texture = partialInit(
			WGPUTextureBindingLayout;
			sampleType = getEnum(WGPUTextureSampleType, args[:sampleType]),
			viewDimension = getEnum(WGPUTextureViewDimension, args[:viewDimension]),
			multisampled = args[:multisampled],
		),
	)
end

function createEntry(::Type{WGPUStorageTextureEntry}; args...)
	# binding,
	# visibility,
	# access::WGPUStorageTextureAccess,
	# format::WGPUTextureFormat;
	# viewDimension::WGPUTextureViewDimension=WGPUTextureViewDimension_2D
	partialInit(
		WGPUBindGroupLayoutEntry;
		binding=args[:binding],
		visibility=getEnum(WGPUShaderStage, args[:visibility]),
		storageTexture = partialInit(
			WGPUStorageTextureBindingLayout;
			access = getEnum(WGPUStorageTextureAccess, args[:access]),
			viewDimension = getEnum(WGPUTextureViewDimension, args[:viewDimension]),
			format = getEnum(WGPUTextureFormat, args[:format])
		)
	)
end

function createBindGroupEntry(::Type{GPUBuffer}; args...)
	partialInit(
		WGPUBindGroupEntry;
		binding = args[:binding],
		buffer = args[:buffer].internal[],
		offset = args[:offset],
		size = args[:size],
		sampler = C_NULL,
		textureView = C_NULL
	)
end

function createBindGroupEntry(::Type{GPUTextureView}; args...)
	partialInit(
		WGPUBindGroupEntry;
		binding = args[:binding],
		textureView = args[:textureView].internal[]
	)
end

function createBindGroupEntry(::Type{GPUSampler}; args...)
	partialInit(
		WGPUBindGroupEntry;
		binding=args[:binding],
		sampler=args[:sampler].internal[]
	)
end

function makeEntryList(entries)
	cEntries = C_NULL
	if length(entries) > 0
		cEntries = WGPUBindGroupLayoutEntry[]
		for entry in entries
			push!(cEntries, createEntry(entry.first; entry.second...))
		end
	end
	return cEntries
end

function createBindGroupLayout(gpuDevice, label, entries)
	bindGroupLayout = C_NULL
	if entries != C_NULL && length(entries) > 0
		bindGroupLayout = wgpuDeviceCreateBindGroupLayout(
			gpuDevice.internal[],
			Ref(partialInit(
				WGPUBindGroupLayoutDescriptor;
				label = pointer(label),
				entries = entries == C_NULL ? C_NULL : pointer(entries), # assuming array of entries
				entryCount = entries == C_NULL ? 0 : length(entries)
			))
		)
	end
	GPUBindGroupLayout(label, Ref(bindGroupLayout), gpuDevice, entries)
end

mutable struct GPUBindGroup
	label
	internal
	layout
	device
	bindings
end

function makeBindGroupEntryList(entries)
	if entries == C_NULL
		return C_NULL
	end
	cEntries = C_NULL
	if length(entries) > 0
		cEntries = WGPUBindGroupEntry[]
		for entry in entries
			push!(cEntries, createBindGroupEntry(entry.first; entry.second...))
		end
	end
	return cEntries
end

function createBindGroup(label, gpuDevice, bindingLayout, entries)
	labelPtr = pointer(label)
	bindGroup = C_NULL
	if entries != C_NULL && length(entries) > 0
		bindGroup = GC.@preserve labelPtr wgpuDeviceCreateBindGroup(
			gpuDevice.internal[],
			Ref(partialInit(
				WGPUBindGroupDescriptor;
				label = labelPtr,
				layout = bindingLayout.internal[],
				entries = entries == C_NULL ? C_NULL : pointer(entries),
				entryCount = entries == C_NULL ? 0 : length(entries)
			))
		)
	end
	GPUBindGroup(label, Ref(bindGroup), bindingLayout, gpuDevice, entries)
end

mutable struct GPUPipelineLayout
	label
	internal
	device
	layouts
end

function createPipelineLayout(gpuDevice, label, bindGroupLayouts)
	labelPtr = pointer(label)
	if bindGroupLayouts == C_NULL
		bindGroupLayoutsPtr = C_NULL
		bindGroupLayoutCount = 0
	else
		bindGroupLayoutsPtr = pointer(bindGroupLayouts)
		bindGroupLayoutCount = length(bindGroupLayouts)
	end
	pipelineDescriptor = GC.@preserve bindGroupLayoutsPtr labelPtr partialInit(
				WGPUPipelineLayoutDescriptor;
				label = labelPtr,
				bindGroupLayouts = bindGroupLayoutsPtr,
				bindGroupLayoutCount = bindGroupLayoutCount
			) |> Ref
	pipelineLayout = wgpuDeviceCreatePipelineLayout(
		gpuDevice.internal[],
		pipelineDescriptor |> pointer_from_objref
	) |> Ref
	GPUPipelineLayout(label, pipelineLayout, gpuDevice, bindGroupLayouts)
end	

mutable struct GPUShaderModule
	label
	internal
	device
end

function loadWGSL(buffer::Vector{UInt8}; name="UnnamedShader")
	b = buffer
	bufPointer = pointer(b)
	wgslDescriptor = GC.@preserve bufPointer Ref(WGPUShaderModuleWGSLDescriptor(
		defaultInit(WGPUChainedStruct),
		bufPointer
	))
	a = partialInit(
		WGPUShaderModuleDescriptor;
		nextInChain = pointer_from_objref(wgslDescriptor),
		label = pointer(name)
	) |> WGPURef
	return (a, wgslDescriptor, names)
end

function loadWGSL(buffer::IOBuffer; name= " UnknownShader ")
	b = read(buffer)
	wgslDescriptor = Ref(WGPUShaderModuleWGSLDescriptor(
		defaultInit(WGPUChainedStruct),
		pointer(b)
	))
	a = partialInit(
		WGPUShaderModuleDescriptor;
		nextInChain = pointer_from_objref(wgslDescriptor),
		label = pointer(name)
	) |> WGPURef
	return (a, wgslDescriptor, names)
end

function loadWGSL(file::IOStream; name= " UnknownShader ")
	b = read(file)
	wgslDescriptor = Ref(WGPUShaderModuleWGSLDescriptor(
		defaultInit(WGPUChainedStruct),
		pointer(b)
	))
	a = partialInit(
		WGPUShaderModuleDescriptor;
		nextInChain = pointer_from_objref(wgslDescriptor),
		label = pointer(name == "UnknownShader" ? file.name : name)
	) |> Ref
	return (a, wgslDescriptor, name)
end

function createShaderModule(
	gpuDevice,
	label,
	shadercode,
	sourceMap,
	hints
)
    shader = GC.@preserve shadercode wgpuDeviceCreateShaderModule(
    	gpuDevice.internal[],
    	pointer_from_objref(shadercode)
    )

	GPUShaderModule(label, Ref(shader), gpuDevice)
end

mutable struct GPUComputePipeline
	label
	internal
	device
	layout
end

mutable struct ComputeStage
	internal
end

function createComputeStage(shaderModule, entryPoint::String)
	computeStage = partialInit(
		WGPUProgrammableStageDescriptor;
		_module = shaderModule.internal[],
		entryPoint = pointer(entryPoint)
	)
	return ComputeStage(Ref(computeStage))
end

function createComputePipeline(gpuDevice, label, pipelinelayout, computeStage)
	computepipeline = wgpuDeviceCreateComputePipeline(
		gpuDevice.internal[],
		Ref(partialInit(
			WGPUComputePipelineDescriptor;
			label = pointer(label),
			layout = pipelinelayout.internal[],
			compute = computeStage.internal[]
		))
	)
	GPUComputePipeline(label, Ref(computepipeline), gpuDevice, pipelinelayout)
end

mutable struct GPUVertexAttribute 
	internal
	strongRefs
end

function createEntry(::Type{GPUVertexAttribute}; args...)
	aRef =	partialInit(
		WGPUVertexAttribute;
		format = getEnum(WGPUVertexFormat, args[:format]),
		offset = args[:offset],
		shaderLocation = args[:shaderLocation]
	)
	return GPUVertexAttribute(aRef |> Ref, args)
end

mutable struct GPUVertexBufferLayout 
	internal
	strongRefs
end

function createEntry(::Type{GPUVertexBufferLayout}; args...)
	attrArray = WGPURef{WGPUVertexAttribute}[]
	attrArrayObjs = GPUVertexAttribute[]
	attributes = args[:attributes]
	
	for attribute in attributes
		obj = createEntry(GPUVertexAttribute; attribute.second...)
		push!(attrArrayObjs, obj)
		push!(attrArray, obj.internal[])
	end
	
	attributesArrayPtr = pointer(map((x) -> x[], attrArray))
	
	aref = partialInit(
		WGPUVertexBufferLayout;
		arrayStride = args[:arrayStride],
		stepMode = getEnum(WGPUVertexStepMode, args[:stepMode]), # TODO default is "vertex"
		attributes = attributesArrayPtr,
		attributeCount = length(attrArray)
	)
	
	return GPUVertexBufferLayout(aref |> Ref, (args , attributesArrayPtr, attrArrayObjs, attrArray) .|> Ref)
end

struct GPUVertexState
	internal
	strongRefs
end

function createEntry(::Type{GPUVertexState}; args...)
	bufferDescArray = WGPURef{WGPUVertexBufferLayout}[]
	buffersArrayObjs = GPUVertexBufferLayout[]
	buffers = args[:buffers]
	entryPointArg = args[:entryPoint]

	for buffer in buffers
		obj = createEntry(buffer.first; buffer.second...)
		push!(buffersArrayObjs, obj)
		push!(bufferDescArray, obj.internal[])
	end

	buffersArray = C_NULL
	if length(buffers) > 0
		buffersArray = pointer(map((x) -> x[], bufferDescArray))
	end

	entryPointPtr = pointer(entryPointArg)
	shader = args[:_module] |> Ref
	shaderInternal = shader[].internal
	aRef = partialInit(
		WGPUVertexState;
		_module = shaderInternal[],
		entryPoint = entryPointPtr,
		buffers = buffersArray,
		bufferCount = length(buffers)
	)
		
	return GPUVertexState(aRef[] |> Ref, (args, entryPointArg, shader, shaderInternal, buffers, buffersArray, buffersArrayObjs, bufferDescArray) .|> Ref)
end

struct GPUPrimitiveState 
	internal
	strongRefs
end

function createEntry(::Type{GPUPrimitiveState}; args...)
	a = partialInit(
		WGPUPrimitiveState;
		topology = getEnum(WGPUPrimitiveTopology, args[:topology]),
		stripIndexFormat = getEnum(WGPUIndexFormat, args[:stripIndexFormat]),
		frontFrace = getEnum(WGPUFrontFace, args[:frontFace]), # TODO 
		cullMode = getEnum(WGPUCullMode, args[:cullMode])
	)
	return GPUPrimitiveState(a, args)
end

struct GPUStencilFaceState 
	internal
	strongRefs
end

function createEntry(::Type{GPUStencilFaceState}; args...)
	a = partialInit(
		WGPUStencilFaceState;
		compare = args[:compare],
		failOp = args[:failOp],
		depthFailOp = args[:depthFailOp],
		passOp = args[:passOp]
	) |> Ref
	return GPUStencilFaceState(a, args)
end

struct GPUDepthStencilState 
	internal
	strongRefs
end

function createEntry(::Type{GPUDepthStencilState}; args...)
	a = nothing
	if length(args) > 0 && args != C_NULL
		aref = Ref(partialInit(
			WGPUDepthStencilState;
			args...
		))
		a = pointer_from_objref(aref) |> Ref
	else
		a = C_NULL |> Ref
	end
	return GPUDepthStencilState(a, args)
end

mutable struct GPUMultiSampleState
	internal
	strongRefs
end

function createEntry(::Type{GPUMultiSampleState}; args...)
	a = partialInit(
		WGPUMultisampleState;
		count = args[:count],
		mask = args[:mask],
		alphaToCoverageEnabled = args[:alphaToCoverageEnabled]
	) |> Ref
	return GPUMultiSampleState(a, args)
end

mutable struct GPUBlendComponent
	internal
	strongRefs
end

function createEntry(::Type{GPUBlendComponent}; args...)
	a = partialInit(
		WGPUBlendComponent;
		srcFactor=getEnum(WGPUBlendFactor, args[:srcFactor]),
		dstFactor=getEnum(WGPUBlendFactor, args[:dstFactor]),
		operation=getEnum(WGPUBlendOperation, args[:operation])
	)
	return GPUBlendComponent(a, args)
end

mutable struct GPUBlendState
	internal
	strongRefs
end

function createEntry(::Type{GPUBlendState}; args...)
	a = partialInit(
		WGPUBlendState;
		color = args[:color],
		alpha = args[:alpha]
	)
	return GPUBlendState(a, args)
end

mutable struct GPUColorTargetState
	internal
	strongRefs
end

function createEntry(::Type{GPUColorTargetState}; args...)
	colorEntry = createEntry(GPUBlendComponent; args[:color]...)
	alphaEntry = createEntry(GPUBlendComponent; args[:alpha]...)
	blendArgs  = [:color=>colorEntry.internal[], :alpha=>alphaEntry.internal[]]
	blend = createEntry(GPUBlendState; blendArgs...)
	kargs = Dict(args)
	kargs[:writeMask] = get(kargs, :writeMask, WGPUColorWriteMask_All)
	blendInternal = blend.internal
	aref =  GC.@preserve blendInternal partialInit(
		WGPUColorTargetState;
		format = args[:format],
		blend = blend.internal |> pointer_from_objref,
		writeMask = kargs[:writeMask]
	)
	return GPUColorTargetState(aref[] |> Ref, (blend, blend.internal, colorEntry, alphaEntry, args) .|> Ref)
end

mutable struct GPUFragmentState 
	internal
	strongRefs
end

function createEntry(::Type{GPUFragmentState}; args...)
	targets = args[:targets]
	ctargets = WGPUColorTargetState[] 
	targetObjs = GPUColorTargetState[]
	for target in targets
		obj = createEntry(target.first; target.second...)
		push!(targetObjs, obj)
		push!(ctargets, obj.internal[])
	end
	entryPointArg = args[:entryPoint]
	entryPointPtr = pointer(entryPointArg)
	shader = args[:_module] |> WGPURef
	shaderInternal = shader[].internal
	aref = GC.@preserve entryPointPtr shaderInternal partialInit(
		WGPUFragmentState;
		_module = shaderInternal[],
		entryPoint = entryPointPtr,
		targets = pointer(ctargets),
		targetCount = length(targets)
	)
	aptrRef = aref |> pointer_from_objref |> (x) -> convert(Ptr{WGPUFragmentState}, x) |> Ref
	return GPUFragmentState(aptrRef, (aref, args, shader, ctargets, targetObjs, entryPointArg, shaderInternal) .|> Ref )
end

mutable struct GPURenderPipeline
	label
	internal
	descriptor
	device
	layout
	vertexState
	primitiveState
	depthStencilState
	MultiSampleState
	FragmentState
end

function createRenderPipeline(
	gpuDevice, 
	pipelinelayout, 
	renderpipeline;
	label="RenderPipeLine"
)
	renderArgs = Dict()
	for state in renderpipeline
		obj = createEntry(state.first; state.second...)
		renderArgs[state.first] = obj.internal
	end
	vertexState = renderArgs[GPUVertexState]
	primitiveState = renderArgs[GPUPrimitiveState]
	depthStencilState = renderArgs[GPUDepthStencilState]
	multiSampleState = renderArgs[GPUMultiSampleState]
	fragmentState = renderArgs[GPUFragmentState]
	pipelineDesc = partialInit(
			WGPURenderPipelineDescriptor;
			label = pointer(label),
			layout = pipelinelayout.internal[],
			vertex = vertexState[],
			primitive = primitiveState[],
			depthStencil = depthStencilState[],
			multisample = multiSampleState[],
			fragment = fragmentState[]
		)
	renderpipeline =  wgpuDeviceCreateRenderPipeline(
		gpuDevice.internal[],
		pipelineDesc |> pointer_from_objref
	) |> Ref
	return GPURenderPipeline(
		label,
		renderpipeline,
		pipelineDesc,
		gpuDevice, 
		pipelinelayout , 
		vertexState , 
		primitiveState , 
		depthStencilState , 
		multiSampleState , 
		fragmentState 
	)
end

mutable struct GPUColorAttachments 
	internal
	strongRefs
end

mutable struct GPUColorAttachment 
	internal
	strongRefs
end

mutable struct GPUDepthStencilAttachment 
	internal
	strongRefs
end

mutable struct GPURenderPassEncoder
	label
	internal
	pipeline
	cmdEncoder
end

function createEntry(::Type{GPUColorAttachment}; args...)
	textureView = args[:view]
	a = partialInit(
		WGPURenderPassColorAttachment;
		view = textureView.internal[],
		resolveTarget = args[:resolveTarget],
		clearValue = WGPUColor(args[:clearValue]...),
		loadOp = args[:loadOp],
		storeOp = args[:storeOp]
	)
	return GPUColorAttachment(a, (args, textureView))
end

function createEntry(::Type{GPUColorAttachments}; args...)
	attachments = WGPURenderPassColorAttachment[]
	attachmentObjs = GPUColorAttachment[]
	for attachment in args[:attachments]
		obj = createEntry(attachment.first; attachment.second...)
		push!(attachmentObjs, obj)
		push!(attachments, obj.internal[])
	end
	return GPUColorAttachments(attachments |> Ref, (attachments, attachmentObjs))
end

function createEntry(::Type{GPUDepthStencilAttachment}; args...)
	if length(args) > 0
		# TODO
	end
	return GPUDepthStencilAttachment(C_NULL |> Ref, nothing)
end

function createRenderPassFromPairs(renderPipeline; label=" RENDER PASS DESCRIPTOR ")
	renderArgs = Dict()
	for config in renderPipeline
		renderArgs[config.first] = createEntry(config.first; config.second...).internal
	end
	# return renderArgs
	colorAttachments = renderArgs[GPUColorAttachments]
	depthStencilAttachment = get(renderArgs, GPUDepthStencilAttachment, C_NULL |> Ref)
	a = partialInit(
		WGPURenderPassDescriptor;
		label = pointer(label),
		colorAttachments = pointer(colorAttachments[]),
		colorAttachmentCount = length(colorAttachments[]),
		depthStencilAttachment = depthStencilAttachment[]
	)
	return (a, colorAttachments, label, depthStencilAttachment, renderArgs)
end

mutable struct GPUCommandBuffer
	label
	internal
	device
end

function createCommandBuffer()

end

mutable struct GPUCommandEncoder
	label
	internal
	device
end

mutable struct GPUComputePassEncoder
	label
	internal
	cmdEncoder
end

function createCommandEncoder(gpuDevice, label)
	labelRef = label |> Ref
	cmdEncDesc = partialInit(
				WGPUCommandEncoderDescriptor;
				label = pointer(label)
			) |> Ref
	commandEncoder = wgpuDeviceCreateCommandEncoder(
		gpuDevice.internal[],
		cmdEncDesc |> pointer_from_objref
	) |> Ref
	return GPUCommandEncoder(label, commandEncoder, gpuDevice)
end

function beginComputePass(cmdEncoder::GPUCommandEncoder; 
			label = " COMPUTE PASS DESCRIPTOR ", 
			timestampWrites = [])
	computePass = wgpuCommandEncoderBeginComputePass(
		cmdEncoder.internal[],
		partialInit(
			WGPUComputePassDescriptor;
			label = pointer(label)
		) |> Ref |> pointer_from_objref
	) |> WGPURef
	GPUComputePassEncoder(label, computePass, cmdEncoder)
end

function beginRenderPass(cmdEncoder::GPUCommandEncoder, renderPipelinePairs; label = " BEGIN RENDER PASS ")
	(req, rest...) = createRenderPassFromPairs(renderPipelinePairs; label = label)
	renderPass = wgpuCommandEncoderBeginRenderPass(
		cmdEncoder.internal[],
		req |> pointer_from_objref
	) |> WGPURef
	GPURenderPassEncoder(label, renderPass, renderPipelinePairs, cmdEncoder)
end

function copyBufferToBuffer(
	cmdEncoder::GPUCommandEncoder,
	source::GPUBuffer,
	sourceOffset::Int,
	destination::GPUBuffer,
	destinationOffset::Int,
	size::Int
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
		size
	)
end

function copyBufferToTexture(
	cmdEncoder::GPUCommandEncoder,
	source::GPUBuffer,
	destination::GPUTexture,
	copySize
)
	
end

function copyTextureToBuffer()

end

function copyTextureToTexture()

end

function finish(cmdEncoder::GPUCommandEncoder; label = " CMD ENCODER COMMAND BUFFER ")
	cmdEncoderFinish = wgpuCommandEncoderFinish(
		cmdEncoder.internal[],
		Ref(partialInit(
			WGPUCommandBufferDescriptor;
			label = pointer(label)
		))
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
	wgpuComputePassEncoderSetPipeline(
		computePass.internal[], 
		pipeline.internal[]
	)
end


function setBindGroup(computePass::GPUComputePassEncoder, 
						index::Int, 
						bindGroup::GPUBindGroup, 
						dynamicOffsetsData::Vector{UInt32}, 
						start::Int, 
						dataLength::Int)
	offsets = pointer(dynamicOffsetsData)
	setbindgroup = wgpuComputePassEncoderSetBindGroup(
		computePass.internal[],
		index,
		bindGroup.internal[],
		length(dynamicOffsetsData),
		offsets,
	)
	return nothing
end


function setBindGroup(renderPass::GPURenderPassEncoder, 
						index::Int, 
						bindGroup::GPUBindGroup, 
						dynamicOffsetsData::Vector{UInt32}, 
						start::Int, 
						dataLength::Int)
	offsets = pointer(dynamicOffsetsData)
	
	setbindgroup = wgpuRenderPassEncoderSetBindGroup(
		renderPass.internal[],
		index,
		bindGroup.internal[],
		length(dynamicOffsetsData),
		offsets,
	)
	return nothing
end


function dispatchWorkGroups(computePass::GPUComputePassEncoder, countX, countY=1, countZ=1)
	wgpuComputePassEncoderDispatch(
		computePass.internal[],
		countX,
		countY,
		countZ
	)
end


function dispatchWorkGroupsIndirect()

end


function endComputePass(computePass::GPUComputePassEncoder)
	wgpuComputePassEncoderEnd(computePass.internal[])
end

function setViewport(renderPass::GPURenderPassEncoder, 
					x, y, 
					width, height, 
					minDepth, maxDepth)
	wgpuRenderPassEncoderSetViewPort(
		renderPass.internal[],
		float(x),
		float(y),
		float(width),
		float(height),
		float(minDepth),
		float(maxDepth)
	)					
end


function setScissorRect(
	renderPass::GPURenderPassEncoder,
	x, y, width, height
)
	wgpuRenderPassEncoderSetScissorRect(
		renderPass.internal[],
		int.([x, y, width, height])...
	)
end

function setPipeline(
	renderPassEncoder::GPURenderPassEncoder, 
	renderpipeline::GPURenderPipeline
)
	wgpuRenderPassEncoderSetPipeline(
		renderPassEncoder.internal[],
		renderpipeline.internal[]
	)	
end

function setIndexBuffer(
	rpe::GPURenderPassEncoder,
	buffer,
	indexFormat;
	offset = 0,
	size = nothing
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
		size
	)
end


function setVertexBuffer(
	rpe::GPURenderPassEncoder,
	slot,
	buffer,
	offset = 0,
	size = nothing
)
	if size == nothing
		size = buffer.size - offset
	end
	wgpuRenderPassEncoderSetVertexBuffer(
		rpe.internal[],
		slot,
		buffer.internal[],
		offset,
		size
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
		firstInstance
	)
end


function drawIndexed(
	renderPassEncoder::GPURenderPassEncoder,
	indexCount;
	instanceCount = 1,
	firstIndex = 0,
	baseVertex = 0,
	firstInstance = 0
)
	wgpuRenderPassEncoderDrawIndexed(
		renderPassEncoder.internal[],
		indexCount,
		instanceCount,
		firstIndex,
		baseVertex,
		firstInstance
	)
end

function endEncoder(
	renderPass::GPURenderPassEncoder
)
	wgpuRenderPassEncoderEnd(
		renderPass.internal[]
	)
end


function submit(queue::GPUQueue, commandBuffers)
	commandBufferListPtr = map((cmdbuf)-> cmdbuf.internal[], commandBuffers)
	GC.@preserve commandBufferListPtr wgpuQueueSubmit(queue.internal[], length(commandBuffers), commandBufferListPtr)
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

	destination = partialInit(
		WGPUImageCopyTexture;
		texture = texture[].internal[],
		mipLevel = mipLevel,
		origin = cOrigin[] 
	) |> Ref
	
	layout = args[:layout]
	for i in layout
		@eval $(i.first) = $(i.second)
	end
	cDataLayout = partialInit(
		WGPUTextureDataLayout;
		offset = offset,
		bytesPerRow = bytesPerRow,
		rowsPerImage = rowsPerImage
	) |> Ref
	texSize = args[:textureSize]
	size = partialInit(
		WGPUExtent3D;
		width = texSize[1],
		height = texSize[2],
		depthOrArrayLayers = texSize[3]
	) |> Ref
	texData = args[:textureData]
	texDataPtr = pointer(texData[])
	dataLength = length(texData[])
	GC.@preserve texDataPtr wgpuQueueWriteTexture(
		queue.internal[],
		destination,
		texDataPtr,
		dataLength,
		cDataLayout,
		size
	)
end

function readTexture()

end


function readBuffer(gpuDevice, buffer, bufferOffset, size)
	# TODO more implementation is required
	# Took shortcut
	usage = ["CopyDst", "MapRead"]
	tmpBuffer = WGPU.createBuffer(" READ BUFFER TEMP ", 
								gpuDevice, 
								size, 
								usage,
								false)
	commandEncoder =  createCommandEncoder(gpuDevice, " READ BUFFER COMMAND ENCODER ")
	copyBufferToBuffer(commandEncoder, buffer, bufferOffset, tmpBuffer, 0, size)
	submit(gpuDevice.queue, [finish(commandEncoder),])
	data = mapRead(tmpBuffer)
	destroy(tmpBuffer)
	return data
end

function writeBuffer(queue::GPUQueue, buffer, bufferOffset, data, dataOffset, size)
	
end


abstract type CanvasInterface end

abstract type GLFWCanvas end

mutable struct GLFWX11Canvas <: GLFWCanvas
	title::String
	size::Tuple
	display
	windowRef # This has to be platform specific may be
	windowX11
	surface
	surfaceDescriptor
	XlibSurface
	needDraw
	requestDrawTimerRunning
	changingPixelRatio
	isMinimized::Bool
	device
	context
	drawFunc
end


function attachDrawFunction(canvas::GLFWCanvas, f)
	if canvas.drawFunc == nothing
		canvas.drawFunc = f
	end
end

function defaultInit(::Type{GLFWX11Canvas})
	displayRef = Ref{Ptr{GLFW.Window}}()
	windowRef = Ref{GLFW.Window}()
	windowX11Ref = Ref{GLFW.Window}()
	surfaceRef = Ref{WGPUSurface}()
	XlibSurfaceRef = Ref{WGPUSurfaceDescriptorFromXlibWindow}()
	surfaceDescriptorRef = Ref{WGPUSurfaceDescriptor}()
	displayRef[] = GLFW.GetX11Display() 
	title = "GLFW WGPU Window"
	windowRef[] = window = GLFW.CreateWindow(1280, 960, title)
	windowX11Ref[] = GLFW.GetX11Window(window)
	XlibSurfaceRef[] = partialInit(
				        WGPUSurfaceDescriptorFromXlibWindow;
				        chain = partialInit(
				            WGPUChainedStruct;
				            next = C_NULL,
				            sType = WGPUSType_SurfaceDescriptorFromXlibWindow
				        ),
				        display = displayRef[],
				        window = windowX11Ref[].handle
				    )
	surfaceDescriptorRef[] = partialInit(
				WGPUSurfaceDescriptor;
				label = C_NULL,
				nextInChain = pointer_from_objref(XlibSurfaceRef) 
		   	)
	surfaceRef[] = 	wgpuInstanceCreateSurface(
	    C_NULL,
		pointer_from_objref(surfaceDescriptorRef)
	)
	title = "GLFW Window"
	canvas = GLFWX11Canvas(
		title,
		(400, 500),
		displayRef,
		windowRef,
		windowX11Ref,
		surfaceRef,
		surfaceDescriptorRef,
		XlibSurfaceRef,
		false,
		nothing,
		false,
		false,
		backend.device,
		nothing,
		nothing
	)
	
	setJoystickCallback(canvas)
	setMonitorCallback(canvas)
	setWindowCloseCallback(canvas)
	setWindowPosCallback(canvas)
	setWindowSizeCallback(canvas)
	setWindowFocusCallback(canvas)
	setWindowIconifyCallback(canvas)
	setWindowMaximizeCallback(canvas)
	setKeyCallback(canvas)
	setCharModsCallback(canvas)
	setMouseButtonCallback(canvas)
	setScrollCallback(canvas)
	setCursorPosCallback(canvas)
	setDropCallback(canvas)

	return canvas
end


function setJoystickCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (joystick, event) -> println("$joystick $event")
	else
		callback = f
	end
	GLFW.SetJoystickCallback(callback)	
end


function setMonitorCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (monitor, event) -> println("$monitor $event")
	else
		callback = f
	end
	GLFW.SetMonitorCallback(callback)	
end

function setWindowCloseCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (event) -> println("Window closed")
	else
		callback = f
	end
	GLFW.SetWindowCloseCallback(canvas.windowRef[], callback)
end

function setWindowPosCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, x, y) -> println("window position : $x $y")
	else
		callback = f
	end
	GLFW.SetWindowPosCallback(canvas.windowRef[], callback)	
end

function setWindowSizeCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, w, h) -> println("window size : $w $h")
	else
		callback = f
	end
	GLFW.SetWindowSizeCallback(canvas.windowRef[], callback)	
end

function setWindowFocusCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, focused) -> println("window focus : $focused")
	else
		callback = f
	end
	GLFW.SetWindowFocusCallback(canvas.windowRef[], callback)	
end

function setWindowIconifyCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, iconified) -> println("window iconify : $iconified")
	else
		callback = f
	end
	GLFW.SetWindowIconifyCallback(canvas.windowRef[], callback)	
end

function setWindowMaximizeCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, maximized) -> println("window maximized : $maximized")
	else
		callback = f
	end
	GLFW.SetWindowMaximizeCallback(canvas.windowRef[], callback)	
end

function setKeyCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, key, scancode, action, mods) -> begin
			name = GLFW.GetKeyName(key, scancode)
			if name == nothing
				println("scancode $scancode ", action)
			else
				println("key $name ", action)
			end
		end
	else
		callback = f
	end
	GLFW.SetKeyCallback(canvas.windowRef[], callback)	
end


function setCharModsCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, c, mods) -> println("char: $c, mods : $mods")
	else
		callback = f
	end
	GLFW.SetCharModsCallback(canvas.windowRef[], callback)	
end

function setMouseButtonCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, button, action, mods) -> println("$button : $action : $mods")
	else
		callback = f
	end
	GLFW.SetMouseButtonCallback(canvas.windowRef[], callback)	
end

function setCursorPosCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, x, y) -> println("cursor $x : $y")
	else
		callback = f
	end
	GLFW.SetCursorPosCallback(canvas.windowRef[], callback)	
end

function setScrollCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, xoff, yoff) -> println("scroll $xoff : $yoff")
	else
		callback = f
	end
	GLFW.SetScrollCallback(canvas.windowRef[], callback)	
end


function setDropCallback(canvas::GLFWCanvas, f=nothing)
	if f==nothing
		callback = (_, paths) -> println("path $paths")
	else
		callback = f
	end
	GLFW.SetDropCallback(canvas.windowRef[], callback)	
end



mutable struct GPUCanvasContext
	canvasRef::Ref{GLFWX11Canvas}
	surfaceSize
	surfaceId
	internal
	currentTexture
	device
	format::WGPUTextureFormat
	usage::WGPUTextureUsage
	colorSpace::WGPUPredefinedColorSpace
	compositingAlphaMode
	size
	physicalSize
	pixelRatio
	logicalSize
end


function getContext(gpuCanvas::GLFWX11Canvas)
	if gpuCanvas.context == nothing
		return partialInit(
			GPUCanvasContext;
			canvasRef = Ref(gpuCanvas),
			surfaceSize = (-1, -1),
			surfaceId = gpuCanvas.surface[],
			internal = nothing,
			device = gpuCanvas.device,
			compositingAlphaMode=nothing
		)
	else
		return gpuCanvas.context
	end
end


function config(a::T; args...) where T
	fields = fieldnames(typeof(a[]))
	for pair in args
		if pair.first in fields
			setproperty!(a[], pair.first, pair.second)
		else
			@error "Cannot set field $pair. Check if its a valid field for $T"
		end
	end
end


function unconfig(a::T) where T
	for field in fieldnames(T)
		setproperty!(a, field, defaultInit(fieldtype(T, field)))
	end
end


function configure(
	canvasContext::GPUCanvasContext;
	device,
	format,
	usage,
	viewFormats,
	colorSpace,
	compositingAlphaMode,
	size
)
	unconfig(canvasContext)
	canvasContext.device = device
	canvasContext.format = format
	canvasContext.usage = usage
	canvasContext.colorSpance = colorSpace
	canvasContext.compositingAlphaMode = compositingAlphaMode
	canvasContext.size = size
end

function unconfigure(canvasContext::GPUCanvasContext)
	canvasContext.device  = nothing
	canvasContext.format = nothing
	canvasContext.usage = nothing
	canvasContext.colorSpance = nothing
	canvasContext.compositingAlphaMode = nothing
	canvasContext.size = nothing
end

function determineSize(cntxt::GPUCanvasContext)
	pixelRatio = GLFW.GetWindowContentScale(cntxt.canvasRef[].windowRef[]) |> first
	psize = GLFW.GetFramebufferSize(cntxt.canvasRef[].windowRef[])
	cntxt.pixelRatio = pixelRatio
	cntxt.physicalSize = psize
	cntxt.logicalSize = (psize.width, psize.height)./pixelRatio
	# TODO skipping event handlers for now
end


function getPreferredFormat(canvasContext::GPUCanvasContext)
	# TODO return srgb
end

function getSurfaceIdFromCanvas(cntxt::GPUCanvasContext)
	# TODO return cntxt
end

function getCurrentTexture(cntxt::GPUCanvasContext)
	if cntxt.device.internal[] == C_NULL
		@error "context must be configured before request for texture"
		return
	end
	if cntxt.currentTexture == nothing
		createNativeSwapChainMaybe(cntxt)
		id = wgpuSwapChainGetCurrentTextureView(cntxt.internal[]) |> Ref
		size = (cntxt.surfaceSize..., 1)
		cntxt.currentTexture = GPUTextureView(
			"swap chain", id, cntxt.device, nothing, size
		)
	end
	return cntxt.currentTexture
end

function present(cntxt::GPUCanvasContext)
	if cntxt.internal[] != C_NULL && cntxt.currentTexture.internal[] != C_NULL
		wgpuSwapChainPresent(cntxt.internal[])
	end
	destroy(cntxt.currentTexture)
	cntxt.currentTexture = nothing
end

function createNativeSwapChainMaybe(canvasCntxt::GPUCanvasContext)
	canvas = canvasCntxt.canvasRef[]
	pSize = canvasCntxt.physicalSize
	if pSize == canvasCntxt.surfaceSize
		return
	end
	canvasCntxt.surfaceSize = pSize
	canvasCntxt.usage = WGPUTextureUsage_RenderAttachment
	presentMode = WGPUPresentMode_Fifo
	swapChain = partialInit(
		WGPUSwapChainDescriptor;
		usage = canvasCntxt.usage,
		format = canvasCntxt.format,
		width = max(1, pSize[1]),
		height = max(1, pSize[2]),
		presentMode = presentMode
	) |> Ref
	if canvasCntxt.surfaceId == nothing
		canvasCntxt.surfaceId = getSurfaceIdFromCanvas(canvas)
	end
	canvasCntxt.internal = wgpuDeviceCreateSwapChain(
		canvasCntxt.device.internal[],
		canvasCntxt.surfaceId,
		swapChain
	) |> Ref
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

end
