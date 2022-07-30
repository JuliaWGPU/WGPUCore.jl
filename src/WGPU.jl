
module WGPU


using CEnum
using GLFW
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

    c_propertiesRef = partialInit(
    	WGPUAdapterProperties
   	) |> Ref
   	
   	c_propertiesPtr = c_propertiesRef |> pointer_from_objref

    wgpuAdapterGetProperties(adapter[], c_propertiesPtr)
    g = convert(Ptr{WGPUAdapterProperties}, c_propertiesPtr)
    h = GC.@preserve c_propertiesPtr unsafe_load(g)
    supportedLimitsRef = partialInit(
    	WGPUSupportedLimits;
   	) |> Ref
    supportedLimitsPtr = supportedLimitsRef |> pointer_from_objref
    GC.@preserve supportedLimitsPtr wgpuAdapterGetLimits(adapter[], supportedLimitsPtr)
    g = convert(Ptr{WGPUSupportedLimits}, supportedLimitsPtr)
    h = GC.@preserve supportedLimitsPtr unsafe_load(g)
    features = []
    partialInit(
		GPUAdapter;
   	    name = "WGPU",
   	    features = features,
   	    internal = adapter,
   	    limits = h.limits,
   	    properties = c_propertiesRef,
   	    options = adapterOptions,
   	    supportedLimits = supportedLimitsRef,
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
   	
    deviceExtras = partialInit(
    	WGPUDeviceExtras;
    	chain = chain[], 
    	nativeFeatures = defaultInit(WGPUNativeFeature), 
    	label = pointer("Device"), 
    	tracePath = pointer(tracepath)
   	)
   	
    wgpuLimits = partialInit(WGPULimits; maxBindGroups = 4) # TODO set limits
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
mutable struct BufferDimensions
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
	texture = GC.@preserve label wgpuDeviceCreateTexture(
		gpuDevice.internal[],
		partialInit(
			WGPUTextureDescriptor;
			label = pointer(label),
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
		bindGroupLayout = GC.@preserve label wgpuDeviceCreateBindGroupLayout(
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
	bindGroup = C_NULL
	if entries != C_NULL && length(entries) > 0
		bindGroup = GC.@preserve label wgpuDeviceCreateBindGroup(
			gpuDevice.internal[],
			Ref(partialInit(
				WGPUBindGroupDescriptor;
				label = pointer(label),
				layout = bindingLayout.internal[],
				entries = entries == C_NULL ? C_NULL : pointer(entries),
				entryCount = entries == C_NULL ? 0 : length(entries)
			))
		)
	end
	GPUBindGroup(label, Ref(bindGroup), bindingLayout, gpuDevice, entries)
end

function makeBindGroupAndLayout(gpuDevice, bindingLayouts, bindings)
	cBindingLayoutsList = Ref(makeEntryList(bindingLayouts))
	cBindingsList = Ref(makeBindGroupEntryList(bindings))
	bindGroupLayout = createBindGroupLayout(gpuDevice, "Bind Group Layout", cBindingLayoutsList[])
	bindGroup = createBindGroup("BindGroup", gpuDevice, bindGroupLayout, cBindingsList[])
	if bindGroupLayout.internal[] == C_NULL
		bindGroupLayouts = []
	else
		bindGroupLayouts = map((x)->x.internal[], [bindGroupLayout,])
	end
	return (bindGroupLayouts, bindGroup)
end

mutable struct GPUPipelineLayout
	label
	internal
	device
	layouts
	descriptor
end

function createPipelineLayout(gpuDevice, label, bindGroupLayouts)
	@assert typeof(bindGroupLayouts) <: Array "bindGroupLayouts should be an array"
	layoutCount = length(bindGroupLayouts)
	pipelineDescriptor = GC.@preserve bindGroupLayouts label partialInit(
				WGPUPipelineLayoutDescriptor;
				label = pointer(label),
				bindGroupLayouts = (layoutCount == 0) ? C_NULL : pointer(bindGroupLayouts),
				bindGroupLayoutCount = layoutCount
			) |> Ref
	pipelineLayout = wgpuDeviceCreatePipelineLayout(
		gpuDevice.internal[],
		pipelineDescriptor
	) |> Ref
	GPUPipelineLayout(label, pipelineLayout, gpuDevice, bindGroupLayouts, pipelineDescriptor)
end	

mutable struct GPUShaderModule
	label
	internal
	device
end

function loadWGSL(buffer::Vector{UInt8}; name=" UnnamedShader ")
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
	)
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
	)
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
    ) |> Ref

	GPUShaderModule(label, shader, gpuDevice)
end

mutable struct GPUComputePipeline
	label
	internal
	device
	layout
end

mutable struct ComputeStage
	internal
	entryPoint
end

function createComputeStage(shaderModule, entryPoint::String)
	computeStage = GC.@preserve entryPoint partialInit(
		WGPUProgrammableStageDescriptor;
		_module = shaderModule.internal[],
		entryPoint = pointer(entryPoint)
	)
	return ComputeStage(computeStage, entryPoint)
end

function createComputePipeline(gpuDevice, label, pipelinelayout, computeStage)
	computepipeline = GC.@preserve label wgpuDeviceCreateComputePipeline(
		gpuDevice.internal[],
		partialInit(
			WGPUComputePipelineDescriptor;
			label = pointer(label),
			layout = pipelinelayout.internal[],
			compute = computeStage.internal[]
		) |> Ref
	)
	GPUComputePipeline(label, Ref(computepipeline), gpuDevice, pipelinelayout)
end

mutable struct GPUVertexAttribute 
	internal
	strongRefs
end

function createEntry(::Type{GPUVertexAttribute}; args...)
	GPUVertexAttribute(
		partialInit(
			WGPUVertexAttribute;
			format = getEnum(WGPUVertexFormat, args[:format]),
			offset = args[:offset],
			shaderLocation = args[:shaderLocation]
		),
		nothing
	)
end

mutable struct GPUVertexBufferLayout 
	internal
	strongRefs
end

function createEntry(::Type{GPUVertexBufferLayout}; args...)
	attributeArray = WGPUVertexAttribute[]
	attributeArgs = args[:attributes]
	attributeObjs = GPUVertexAttribute[]
	
	for attribute in attributeArgs
		obj = createEntry(GPUVertexAttribute; attribute.second...)
		push!(attributeArray, obj.internal[])
		push!(attributeObjs, obj)
	end
	
	aref = GC.@preserve attributeArray partialInit(
		WGPUVertexBufferLayout;
		arrayStride = args[:arrayStride],
		stepMode = getEnum(WGPUVertexStepMode, args[:stepMode]),
		attributes = pointer(attributeArray),
		attributeCount = length(attributeArray),
		xref1 = attributeArray |> Ref,
	)
	return GPUVertexBufferLayout(aref, (attributeArray |> Ref, attributeObjs .|> Ref))
end

mutable struct GPUVertexState
	internal
	strongRefs
end

function createEntry(::Type{GPUVertexState}; args...)
	bufferDescArray = WGPUVertexBufferLayout[]
	buffersArrayObjs = GPUVertexBufferLayout[]
	buffers = args[:buffers]
	entryPointArg = args[:entryPoint]

	for buffer in buffers
		obj = createEntry(buffer.first; buffer.second...)
		push!(buffersArrayObjs, obj)
		push!(bufferDescArray, obj.internal[])
	end
	
	entryPointPtr = pointer(entryPointArg)

	shader = args[:_module]
	if shader != C_NULL
		shaderInternal = shader.internal
	else
		shaderInternal = C_NULL |> Ref
	end
	
	aRef = GC.@preserve entryPointPtr bufferDescArray partialInit(
		WGPUVertexState;
		_module = shaderInternal[],
		entryPoint = entryPointPtr,
		buffers = length(buffers) == 0 ? C_NULL : pointer(bufferDescArray),
		bufferCount = length(buffers),
		xref1 = bufferDescArray,
		xref2 = shader,
	)
	GPUVertexState(aRef, (bufferDescArray, buffersArrayObjs .|> Ref, entryPointArg, args))
end

mutable struct GPUPrimitiveState 
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

mutable struct GPUStencilFaceState 
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

mutable struct GPUDepthStencilState
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
		writeMask = kargs[:writeMask],
		xref1 = colorEntry,
		xref2 = alphaEntry,
		xref3 = blend
	)
	return GPUColorTargetState(aref[] |> Ref, (blend, blend.internal, colorEntry, alphaEntry, args) .|> Ref)
end

mutable struct GPUFragmentState 
	internal
	strongRefs
end

function createEntry(::Type{GPUFragmentState}; args...)
	targetsArg = args[:targets]
	ctargets = WGPUColorTargetState[] 
	targetObjs = GPUColorTargetState[]
	
	for target in targetsArg
		obj = createEntry(target.first; target.second...)
		push!(targetObjs, obj)
		push!(ctargets, obj.internal[])
	end
	entryPointArg = args[:entryPoint]
	shader = args[:_module] |> WGPURef
	shaderInternal = shader[].internal
	aref = GC.@preserve entryPointArg ctargets shaderInternal partialInit(
		WGPUFragmentState;
		_module = shaderInternal[],
		entryPoint = pointer(entryPointArg),
		targets = pointer(ctargets),
		targetCount = length(targetsArg)
	)
	aptrRef = aref |> pointer_from_objref |> Ref# |> (x) -> convert(Ptr{WGPUFragmentState}, x) |> Ref
	return GPUFragmentState(aptrRef, (aref, args, shader, entryPointArg |> Ref, targetsArg, ctargets .|> Ref, targetObjs .|>Ref, entryPointArg, shaderInternal) .|> Ref )
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

	pipelineDesc = GC.@preserve label partialInit(
		WGPURenderPipelineDescriptor;
		label = pointer(label),
		layout = pipelinelayout.internal[],
		vertex = vertexState[],
		primitive = primitiveState[],
		depthStencil = depthStencilState[],
		multisample = multiSampleState[],
		fragment = fragmentState[]
	)
	
	renderpipeline =  GC.@preserve pipelineDesc wgpuDeviceCreateRenderPipeline(
		gpuDevice.internal[],
		pipelineDesc |> pointer_from_objref
	) |> Ref
	
	return GPURenderPipeline(
		label,
		renderpipeline,
		pipelineDesc |> Ref,
		gpuDevice, 
		pipelinelayout |> Ref , 
		vertexState |> Ref, 
		primitiveState |> Ref, 
		depthStencilState |> Ref, 
		multiSampleState |> Ref, 
		fragmentState |> Ref 
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
	desc
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
	return GPUColorAttachments(attachments |> Ref, (attachments, attachmentObjs) .|> Ref)
end

function createEntry(::Type{GPUDepthStencilAttachment}; args...)
	if length(args) > 0
		# TODO
	end
	return GPUDepthStencilAttachment(C_NULL |> Ref, nothing)
end

mutable struct RenderPassDescriptor
	internal
	colorAttachments
	label
	depthStencilAttachment
	renderArgs
end

function createRenderPassFromPairs(renderPipeline; label=" RENDER PASS DESCRIPTOR ")
	renderArgs = Dict()
	for config in renderPipeline
		renderArgs[config.first] = createEntry(config.first; config.second...).internal
	end
	# return renderArgs
	colorAttachmentsIn = renderArgs[GPUColorAttachments]
	depthStencilAttachment = get(renderArgs, GPUDepthStencilAttachment, C_NULL |> Ref)
	a = GC.@preserve label colorAttachmentsIn partialInit(
		WGPURenderPassDescriptor;
		label = pointer(label),
		colorAttachments = pointer(colorAttachmentsIn[]),
		colorAttachmentCount = length(colorAttachmentsIn[]),
		depthStencilAttachment = depthStencilAttachment[]
	)
	return RenderPassDescriptor(a, colorAttachmentsIn, label, depthStencilAttachment, renderArgs)
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
	desc
end

mutable struct GPUComputePassEncoder
	label
	internal
	cmdEncoder
	desc
end

function createCommandEncoder(gpuDevice, label)
	labelRef = label |> Ref
	cmdEncDesc = GC.@preserve label partialInit(
				WGPUCommandEncoderDescriptor;
				label = pointer(label)
			) |> Ref
	commandEncoder = wgpuDeviceCreateCommandEncoder(
		gpuDevice.internal[],
		cmdEncDesc |> pointer_from_objref
	) |> Ref
	return GPUCommandEncoder(label, commandEncoder, gpuDevice, cmdEncDesc)
end

function beginComputePass(cmdEncoder::GPUCommandEncoder; 
			label = " COMPUTE PASS DESCRIPTOR ", 
			timestampWrites = [])
	desc = GC.@preserve label partialInit(
		WGPUComputePassDescriptor;
		label = pointer(label)
	) |> Ref |> pointer_from_objref
	computePass = wgpuCommandEncoderBeginComputePass(
		cmdEncoder.internal[],
		desc
	) |> Ref
	GPUComputePassEncoder(label, computePass, cmdEncoder, desc)
end

function beginRenderPass(cmdEncoder::GPUCommandEncoder, renderPipelinePairs; label = " BEGIN RENDER PASS ")
	desc = createRenderPassFromPairs(renderPipelinePairs; label = label)
	renderPass = wgpuCommandEncoderBeginRenderPass(
		cmdEncoder.internal[],
		desc.internal |> pointer_from_objref
	) |> WGPURef
	GPURenderPassEncoder(label, renderPass, renderPipelinePairs, cmdEncoder, desc)
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
	source::Dict{Symbol, Any}, 
	destination::Dict{Symbol, Any}, 
	copySize::Dict{Symbol, Int64}
)
	rowAlignment = 256
	bytesPerRow = source[:layout][:bytesPerRow]
	@assert bytesPerRow % rowAlignment == 0 "BytesPerRow must be multiple of $rowAlignment"
	origin = get(source, :origin, [:x=>0, :y=>0, :z=>0] |> Dict)
	cOrigin = partialInit(
		WGPUOrigin3D;
		origin...
	)
	cDestination = partialInit(
		WGPUImageCopyTexture;
		texture = source[:texture].internal[],
		mipLevel = get(source, :mipLevel, 0),
		origin = cOrigin,
		aspect = getEnum(WGPUTextureAspect, "All")
	) |> pointer_from_objref
	cSource = partialInit(
		WGPUImageCopyBuffer;
		buffer = destination[:buffer].internal[],
		layout = partialInit(
			WGPUTextureDataLayout;
			destination[:layout]...
		)
	) |> pointer_from_objref
	cCopySize = partialInit(
		WGPUExtent3D;
		copy...
	) |> pointer_from_objref

	wgpuCommandEncoderCopyBufferToTexture(
		cmdEncoder.internal[],
		cSource,
		cDestination,
		cCopySize
	)
end

function copyTextureToBuffer(
	cmdEncoder::GPUCommandEncoder, 
	source::Dict{Symbol, Any}, 
	destination::Dict{Symbol, Any}, 
	copySize::Dict{Symbol, Int64}
)
	rowAlignment = 256
	dest = Dict(destination)
	bytesPerRow = dest[:layout][:bytesPerRow]
	@assert bytesPerRow % rowAlignment == 0 "BytesPerRow must be multiple of $rowAlignment"
	origin = get(source, :origin, [:x=>0, :y=>0, :z=>0] |> Dict)
	cOrigin = partialInit(
		WGPUOrigin3D;
		origin...
	)
	cSource = partialInit(
		WGPUImageCopyTexture;
		texture = source[:texture].internal[],
		mipLevel = get(source, :mipLevel, 0),
		origin = cOrigin,
		aspect = getEnum(WGPUTextureAspect, "All")
	) |> pointer_from_objref
	cDestination = partialInit(
		WGPUImageCopyBuffer;
		buffer = destination[:buffer].internal[],
		layout = partialInit(
			WGPUTextureDataLayout;
			destination[:layout]... # should document these obscure
		)
	) |> pointer_from_objref
	cCopySize = partialInit(
		WGPUExtent3D;
		copySize...
	) |> pointer_from_objref

	wgpuCommandEncoderCopyTextureToBuffer(
		cmdEncoder.internal[],
		cSource,
		cDestination,
		cCopySize
	)
end

function copyTextureToTexture(
	cmdEncoder::GPUCommandEncoder, 
	source::Dict{Symbol, Any}, 
	destination::Dict{Symbol, Any}, 
	copySize::Dict{Symbol, Int64}
)
	origin1 = get(source, :origin, [:x=>0, :y=>0, :z=>0])
	cOrigin1 = partialInit(
		WGPUOrigin3D;
		origin1...
	)

	cSource = partialInit(
		WGPUImageCopyTexture;
		texture = source[:texture].internal[],
		mipLevel = get(source, :mipLevel, 0),
		origin = COrigin1
	) |> pointer_from_objref

	origin2 = get(destination, :origin, [:x => 0, :y =>0, :z => 0])

	cOrigin2 = partialInit(
		WGPUOrigin3D;
		origin2...
	)

	cDestination = partialInit(
		WGPUImageCopyTexture;
		texture = destination[:texture].internal[],
		mipLevel = get(destination, :mipLevel, 0),
		origin = cOrigin2
	) |> pointer_from_objref

	cCopySize = partialInit(
		WGPUExtent3D;
		copySize...
	) |> pointer_from_objref

	wgpuCommandEncoderCopyTextureToTexture(
		cmdEncoder.internal[],
		cSource,
		cDestination,
		cCopySize
	)
	
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
	offsetcount = length(dynamicOffsetsData)
	setbindgroup = wgpuRenderPassEncoderSetBindGroup(
		computePass.internal[],
		index,
		bindGroup.internal[],
		offsetcount,
		(offsetcount == 0) ? C_NULL : pointer(dynamicOffsetsData)
	)
	return nothing
end

function setBindGroup(renderPass::GPURenderPassEncoder, 
						index::Int, 
						bindGroup::GPUBindGroup, 
						dynamicOffsetsData::Vector{UInt32}, 
						start::Int, 
						dataLength::Int)
	offsetcount = length(dynamicOffsetsData)
	setbindgroup = wgpuRenderPassEncoderSetBindGroup(
		renderPass.internal[],
		index,
		bindGroup.internal[],
		offsetcount,
		offsetcount == 0 ? C_NULL : pointer(dynamicOffsetsData)
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

function dispatchWorkGroupsIndirect(computePass::GPUComputePassEncoder, indirectBuffer, indirectOffset)
	bufferId = indirectBuffer.internal[]
	wgpuComputePassEncoderDispatchIndirect(
		computePass.internal[],
		bufferId,
		indirectOffset
	)
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

forceOffscreen = false

if forceOffscreen == true
	include("offscreen.jl")
elseif Sys.isapple()
	include("glfw.jl")
elseif Sys.islinux()
	include("glfw.jl")
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
