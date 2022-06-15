
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
struct WGPUBackend <: WGPUAbstractBackend
    adapter
    device
end


struct GPUAdapter
    name
    features
    internal
    limits
    properties
end


struct GPUDevice
    label
    internal
    adapter
    features
    limits
    queue
end


struct GPUQueue
    label
    internal
    device
end


struct GPUBuffer
	label
	internal
	device
	size
	usage
end


asyncstatus = Ref(WGPUBufferMapAsyncStatus(3))


function bufferCallback(
	status::WGPUBufferMapAsyncStatus,
	userData
)
	asyncstatus[] = status
	return nothing
end


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

	src_ptr = wgpuBufferGetMappedRange(gpuBuffer.internal[], 0, bufferSize)
	src_ptr = convert(Ptr{UInt8}, src_ptr)
	unsafe_copyto!(pointer(data), src_ptr, bufferSize)
	wgpuBufferUnmap(gpuBuffer.internal[])
	return data
end


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

	src_ptr = wgpuBufferGetMappedRange(gpuBuffer.internal, 0, bufferSize)
	src_ptr = convert(Ptr{UInt8}, src_ptr)
	unsafe_copyto!(src_ptr, pointer(data), bufferSize)
	wgpuBufferUnmap(gpuBuffer.internal)
	return nothing
end


function destroy(gpuBuffer::GPUBuffer)
	if gpuBuffer.internal[] != C_NULL
		tmpBuffer = gpuBuffer.internal[]
		gpuBuffer.internal[] = C_NULL
		wgpuBufferDrop(tmpBuffer)
	end
end



defaultInit(::Type{WGPUBackend}) = begin
    adapter = defaultInit(WGPUAdapter)
    device = defaultInit(WGPUDevice)
    return WGPUBackend(Ref(adapter), Ref(device))
end

##
function getAdapterCallback(adapter::Ref{WGPUAdapter})
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
function getDeviceCallback(device::Ref{WGPUDevice})
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

const backend = defaultInit(WGPUBackend)

defaultInit(::Type{WGPUBackendType}) = WGPUBackendType_WebGPU

function requestAdapter(; canvas=nothing, powerPreference = defaultInit(WGPUPowerPreference))
    adapterExtras = partialInit(
    	WGPUAdapterExtras;
    	chain = partialInit(
    		WGPUChainedStruct;
			sType = WGPUSType(Int64(WGPUSType_AdapterExtras))
		)
	) |> Ref |> pointer_from_objref

    adapterOptions = partialInit(
    	WGPURequestAdapterOptions;
		nextInChain=C_NULL,
		powerPreference=powerPreference,
		forceFallbackAdapter=false
	) |> Ref

    requestAdapterCallback = @cfunction(
    	getAdapterCallback(backend.adapter),
   		Cvoid,
   		(WGPURequestAdapterStatus, WGPUAdapter, Ptr{Cchar}, Ptr{Cvoid})
   	)
   	
    wgpuInstanceRequestAdapter(
    	C_NULL,
        adapterOptions,
        requestAdapterCallback,
        backend.adapter
    )

    c_properties = partialInit(
    	WGPUAdapterProperties
   	) |> Ref |> pointer_from_objref

    wgpuAdapterGetProperties(backend.adapter[], c_properties)
    g = convert(Ptr{WGPUAdapterProperties}, c_properties)
    h = GC.@preserve unsafe_load(g)
    supportedLimits = partialInit(
    	WGPUSupportedLimits;
   	) |> Ref |> pointer_from_objref
    
    wgpuAdapterGetLimits(backend.adapter[], supportedLimits)

    g = convert(Ptr{WGPUSupportedLimits}, supportedLimits)
    GC.@preserve g h =  unsafe_load(g)
    features = []
    GPUAdapter("WGPU", features, backend.adapter, h.limits, c_properties)
end

function requestDevice(gpuAdapter::GPUAdapter;
		label="", 
        requiredFeatures=[], 
        requiredLimits=[],
        defaultQueue=[],
        tracepath = "")
    # TODO trace path
    # Drop devices TODO
    # global backend
    chain = WGPUChainedStruct(C_NULL, WGPUSType(Int32(WGPUSType_DeviceExtras))) |> Ref
    deviceName = pointer("Device") |> Ref
    deviceExtras = WGPUDeviceExtras(chain[], defaultInit(WGPUNativeFeature), deviceName[], pointer(tracepath)) |> Ref
    wgpuLimits = partialInit(WGPULimits; maxBindGroups = 2) |> Ref # TODO set limits
    wgpuRequiredLimits = WGPURequiredLimits(C_NULL, wgpuLimits[]) |> Ref
    wgpuQueueDescriptor = WGPUQueueDescriptor(C_NULL, pointer("default_queue")) |> Ref
    wgpuDeviceDescriptor = Ref(
    	partialInit(
	        WGPUDeviceDescriptor;
	        label = pointer(label),
	        nextInChain = partialInit(
	        	WGPUChainedStruct;
                chain=deviceExtras[]
            ) |> Ref |> pointer_from_objref,
	        requiredFeaturesCount=0,
	        requiredLimits = pointer_from_objref((wgpuRequiredLimits)),
	        defaultQueue = wgpuQueueDescriptor[]
		)
	)
	
    requestDeviceCallback = @cfunction(getDeviceCallback(backend.device), Cvoid, (WGPURequestDeviceStatus, WGPUDevice, Ptr{Cchar}, Ptr{Cvoid}))
    # TODO dump all the info to a string or add it to the GPUAdapter structure
 
    wgpuAdapterRequestDevice(
                gpuAdapter.internal[],
                wgpuDeviceDescriptor,
                requestDeviceCallback,
                backend.device
               )

    supportedLimits = partialInit(
    	WGPUSupportedLimits;
   	) |> Ref |> pointer_from_objref |> Ref
    wgpuDeviceGetLimits(backend.device[], supportedLimits[])
    g = convert(Ptr{WGPUSupportedLimits}, supportedLimits[])
    GC.@preserve g h = unsafe_load(g)
    features = []
    deviceQueue = Ref(wgpuDeviceGetQueue(backend.device[]))
    queue = GPUQueue(" ", deviceQueue, nothing)
    GPUDevice("WGPU", backend.device, backend.adapter, features, h.limits, queue)
#    return backend
end

function createBuffer(label, gpuDevice, size, usage, mappedAtCreation)
    buffer = GC.@preserve label wgpuDeviceCreateBuffer(
    	gpuDevice.internal[],
    	partialInit(WGPUBufferDescriptor;
			label = pointer(label),
			size = size,
			usage = getEnum(WGPUBufferUsage, usage),
			mappedAtCreation = mappedAtCreation
    	) |> Ref
    ) |> Ref
    GPUBuffer(label, buffer, gpuDevice, size, usage)
end

function getDefaultDevice(;backend=backend)
	adapter = WGPU.requestAdapter()
	defaultDevice = requestDevice(adapter)
	return defaultDevice
end

function createBufferWithData(gpuDevice, label, data, usage)
	bufSize = sizeof(data)
	buffer = createBuffer(label, gpuDevice, bufSize, usage, true)
	src_ptr = pointer(data)
	dst_ptr = wgpuBufferGetMappedRange(buffer.internal[], 0, bufSize)
	dst_ptr = oftype(src_ptr, dst_ptr)
	GC.gc(true)
	GC.@preserve buffer src_ptr dst_ptr data unsafe_copyto!(dst_ptr, pointer(data), bufSize)
	wgpuBufferUnmap(buffer.internal[])
	return buffer
end

## TODO
function computeWithBuffers(
	inputArrays::Dict{Int, Array},
	outputArrays::Dict{Int, Union{Int, Tuple}}
)
	
end

## 
struct GPUTexture
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
	bufferDimensions = BufferDimensions(size[1], size[2])
	@info bufferDimensions
	bufferSize = bufferDimensions.padded_bytes_per_row*bufferDimensions.height
	@info bufferSize
	@info size
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
struct GPUTextureView
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
struct GPUSampler
	label
	internal
	device
end

function createSampler(gpuDevice;
				label = " ", 
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

struct GPUBindGroupLayout
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

struct GPUBindGroup
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

struct GPUPipelineLayout
	label
	internal
	device
	layouts
end

function createPipelineLayout(gpuDevice, label, bindGroupLayouts)
	labelRef = Ref(label)
	if bindGroupLayouts == C_NULL
		bindGroupLayoutsPtr = C_NULL
		bindGroupLayoutCount = 0
	else
		bindGroupLayoutsPtr = pointer(bindGroupLayouts)
		bindGroupLayoutCount = length(bindGroupLayouts)
	end
	pipelineDescriptor = GC.@preserve label partialInit(
				WGPUPipelineLayoutDescriptor;
				label = pointer(label),
				bindGroupLayouts = bindGroupLayoutsPtr,
				bindGroupLayoutCount = bindGroupLayoutCount
			) |> Ref
	pipelineLayout = wgpuDeviceCreatePipelineLayout(
		gpuDevice.internal[],
		pipelineDescriptor |> pointer_from_objref
	) |> Ref
	GPUPipelineLayout(label, pipelineLayout, gpuDevice, bindGroupLayouts)
end	

struct GPUShaderModule
	label
	internal
	device
end

function loadWGSL(buffer::Vector{UInt8}; name="UnnamedShader")
	b = buffer
	wgslDescriptor = Ref(WGPUShaderModuleWGSLDescriptor(
		defaultInit(WGPUChainedStruct),
		pointer(b)
	))
	a = partialInit(
		WGPUShaderModuleDescriptor;
		nextInChain = pointer_from_objref(wgslDescriptor),
		label = pointer(name)
	) |> Ref
	return (a, wgslDescriptor)
end

function loadWGSL(buffer::IOBuffer; name= " ")
	b = read(buffer)
	wgslDescriptor = Ref(WGPUShaderModuleWGSLDescriptor(
		defaultInit(WGPUChainedStruct),
		pointer(b)
	))
	a = partialInit(
		WGPUShaderModuleDescriptor;
		nextInChain = pointer_from_objref(wgslDescriptor),
		label = pointer(name)
	) |> Ref
	return (a, wgslDescriptor)
end

function loadWGSL(file::IOStream; name= " ")
	b = read(file)
	wgslDescriptor = Ref(WGPUShaderModuleWGSLDescriptor(
		defaultInit(WGPUChainedStruct),
		pointer(b)
	))
	a = partialInit(
		WGPUShaderModuleDescriptor;
		nextInChain = pointer_from_objref(wgslDescriptor),
		label = pointer(name == " " ? file.name : name)
	) |> Ref
	return (a, wgslDescriptor)
end

function createShaderModule(
	gpuDevice,
	label,
	shadercode,
	sourceMap,
	hints
)
    shader = wgpuDeviceCreateShaderModule(
    	gpuDevice.internal[],
    	pointer_from_objref(shadercode)
    )

	GPUShaderModule(label, Ref(shader), gpuDevice)
end

struct GPUComputePipeline
	label
	internal
	device
	layout
end

struct ComputeStage
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


struct GPUVertexAttribute end

function createEntry(::Type{GPUVertexAttribute}; args...)
	a =	partialInit(
		WGPUVertexAttribute;
		format = getEnum(WGPUVertexFormat, args[:format]),
		offset = args[:offset],
		shaderLocation = args[:shaderLocation]
	) |> Ref
	return (a, args)
end

struct GPUVertexBufferLayout end

function createEntry(::Type{GPUVertexBufferLayout}; args...)
	argsRef = args
	attrArray = WGPUVertexAttribute[]
	attributesArray = Ref(attrArray)
	attributes = Ref(args[:attributes])
	for attribute in attributes[]
		(ret, rest...) = createEntry(GPUVertexAttribute; attribute.second...)
		push!(attributesArray[], ret[])
		@info "GPUVertexOutput" ret[]
	end
	aref = GC.@preserve attrArray partialInit(
		WGPUVertexBufferLayout;
		arrayStride = args[:arrayStride],
		stepMode = getEnum(WGPUVertexStepMode, args[:stepMode]), # TODO default is "vertex"
		attributes = pointer(attributesArray[]),
		attributeCount = length(attributesArray[])
	) |> Ref 
	return (aref, attrArray, attributesArray, attributes, argsRef)
end

struct GPUVertexState end

function createEntry(::Type{GPUVertexState}; args...)
	argsRef = Ref(args)
	bufferDescArray = WGPUVertexBufferLayout[]
	buffersDescriptorArray = bufferDescArray |> Ref
	buffers = Ref(args[:buffers])
	for buffer in buffers[]
		(req, rest...) = createEntry(buffer.first; buffer.second...)
		push!(buffersDescriptorArray[], req[])
	end
	if length(buffers[]) == 0
		buffersArray = C_NULL
	else
		buffersArray = pointer(buffersDescriptorArray[])
	end
	entryPointArg = args[:entryPoint]

	GC.gc(true)
	bufferLayout = buffersDescriptorArray[]
	layout = unsafe_load(pointer(bufferLayout))

	@info "bufferLayout" layout (fieldnames(typeof(layout))) (layout.stepMode) (layout.attributeCount)

	t = GC.@preserve buffersArray unsafe_wrap(Array{WGPUVertexBufferLayout}, buffersArray, 1) 
	b1 = GC.@preserve layout unsafe_load(layout.attributes, 1)
	b2 = GC.@preserve layout unsafe_load(layout.attributes, 2)
	
	@info "BufferLayoutArray" t
	@info "AttributeArray" b1 b2
	
	aref = GC.@preserve bufferDescArray partialInit(
		WGPUVertexState;
		_module = args[:_module].internal[],
		entryPoint = pointer(entryPointArg),
		buffers = buffersDescriptorArray |> getindex |> pointer,
		bufferCount = length(buffers[])
	) |> Ref
	
	return (aref, bufferDescArray, buffersDescriptorArray, buffers, buffersArray, argsRef, entryPointArg)
end

struct GPUPrimitiveState end

function createEntry(::Type{GPUPrimitiveState}; args...)
	a = partialInit(
		WGPUPrimitiveState;
		topology = getEnum(WGPUPrimitiveTopology, args[:topology]),
		stripIndexFormat = getEnum(WGPUIndexFormat, args[:stripIndexFormat]),
		frontFrace = getEnum(WGPUFrontFace, args[:frontFace]), # TODO 
		cullMode = getEnum(WGPUCullMode, args[:cullMode])
	) |> Ref
	return (a, nothing)
end

struct GPUStencilFaceState end

function createEntry(::Type{GPUStencilFaceState}; args...)
	a = partialInit(
		WGPUStencilFaceState;
		compare = args[:compare],
		failOp = args[:failOp],
		depthFailOp = args[:depthFailOp],
		passOp = args[:passOp]
	) |> Ref
	return (a, nothing)
end

struct GPUDepthStencilState end

function createEntry(::Type{GPUDepthStencilState}; args...)
	a = nothing
	if length(args) > 0
		aref = Ref(partialInit(
			WGPUDepthStencilState;
			args...
		))
		a = pointer_from_objref(aref) |> Ref
	else
		a = C_NULL |> Ref
	end
	return (a, nothing)
end

struct GPUMultiSampleState end

function createEntry(::Type{GPUMultiSampleState}; args...)
	a = partialInit(
		WGPUMultisampleState;
		count = args[:count],
		mask = args[:mask],
		alphaToCoverageEnabled = args[:alphaToCoverageEnabled]
	) |> Ref
	return (a, nothing)
end

struct GPUBlendComponent end

function createEntry(::Type{GPUBlendComponent}; args...)
	a = partialInit(
		WGPUBlendComponent;
		srcFactor=getEnum(WGPUBlendFactor, args[:srcFactor]),
		dstFactor=getEnum(WGPUBlendFactor, args[:dstFactor]),
		operation=getEnum(WGPUBlendOperation, args[:operation])
	) |> Ref
	return (a, nothing)
end

struct GPUBlendState end

function createEntry(::Type{GPUBlendState}; args...)
	a = partialInit(
		WGPUBlendState;
		color = args[:color],
		alpha = args[:alpha]
	) |> Ref
	return (a, nothing)
end

struct GPUColorTargetState end

function createEntry(::Type{GPUColorTargetState}; args...)
	colorEntry = (createEntry(GPUBlendComponent; args[:color]...) |> first)[]
	alphaEntry = (createEntry(GPUBlendComponent; args[:alpha]...) |> first)[]
	blendArgs  = [:color=>colorEntry, :alpha=>alphaEntry]
	blend = createEntry(GPUBlendState; blendArgs...) |> first |> pointer_from_objref
	kargs = Dict(args)
	kargs[:writeMask] = get(kargs, :writeMask, WGPUColorWriteMask_All)
	aref =  partialInit(
		WGPUColorTargetState;
		format = args[:format],
		blend = blend,
		writeMask = kargs[:writeMask]
	) |> Ref
	return (aref, blend, colorEntry, alphaEntry, kargs)
end

struct GPUFragmentState end

function createEntry(::Type{GPUFragmentState}; args...)
	argsRef = Ref(args)
	targets = args[:targets]
	ctargets = WGPUColorTargetState[] |> Ref
	for target in targets
		(required, leftover...) = createEntry(target.first; target.second...)
		push!(ctargets[], required[])
	end
	entryPointArg = args[:entryPoint]
	entryPointRef = Ref(pointer(entryPointArg))
	aref = GC.@preserve entryPointArg partialInit(
		WGPUFragmentState;
		_module = args[:_module].internal[],
		entryPoint = entryPointRef[],
		targets = pointer(ctargets[]),
		targetCount = length(ctargets[])
	) |> Ref
	aptrRef = aref |> pointer_from_objref |> Ref
	return (aptrRef, aref, ctargets, targets, argsRef, entryPointArg, entryPointRef)
end

struct GPURenderPipeline
	label
	internal
	device
	layout
end

function createRenderPipelineFromPairs(
	gpuDevice, 
	pipelinelayout, 
	renderpipeline; 
	label="RenderPipeLine"
)	
	renderArgs = Ref(Dict())
	renderArgsRef = renderArgs[]
	for state in renderpipeline
		(req, rest...) = createEntry(state.first; state.second...)
		renderArgsRef[state.first] = req
	end
	a = GC.@preserve renderArgs label createRenderPipeline(
		gpuDevice,
		label,
		pipelinelayout,
		renderArgsRef[GPUVertexState],
		renderArgsRef[GPUPrimitiveState],
		renderArgsRef[GPUDepthStencilState],
		renderArgsRef[GPUMultiSampleState],
		renderArgsRef[GPUFragmentState]
	)
	return (a, renderArgs) |> first
end

function createRenderPipeline(
			gpuDevice, 
			label, 
			pipelinelayout, 
			vertexState,
			primitiveState, 
			depthStencilState,
			multiSampleState,
			fragmentState)

	labelRef = Ref(label)

	renderpipeline = GC.@preserve label wgpuDeviceCreateRenderPipeline(
		gpuDevice.internal[],
		partialInit(
			WGPURenderPipelineDescriptor;
			label = pointer(label),
			layout = pipelinelayout.internal[],
			vertex = vertexState[],
			primitive = primitiveState[],
			depthStencil = depthStencilState[],
			multisample = multiSampleState[],
			fragment = fragmentState[]
		) |> Ref
	) |> Ref
	return GPURenderPipeline(label, renderpipeline, gpuDevice, pipelinelayout)
end

struct GPUColorAttachments end
struct GPUColorAttachment end

struct GPUDepthStencilAttachment end

struct GPURenderPassEncoder
	label
	internal
	pipeline
	cmdEncoder
end

function createEntry(::Type{GPUColorAttachment}; args...)
	argsRef = args |> Ref
	textureView = args[:view]
	a = partialInit(
		WGPURenderPassColorAttachment;
		view = textureView.internal[],
		resolveTarget = args[:resolveTarget],
		clearValue = WGPUColor(args[:clearValue]...),
		loadOp = args[:loadOp],
		storeOp = args[:storeOp]
	) |> Ref
	return (a, argsRef, args, textureView)
end

function createEntry(::Type{GPUColorAttachments}; args...)
	argsRef = args |> Ref
	attachments = WGPURenderPassColorAttachment[] |> Ref
	for attachment in args[:attachments]
		(req, rest...) = createEntry(attachment.first; attachment.second...)
		push!(attachments[], req[])
	end
	return (attachments, nothing)
end

function createEntry(::Type{GPUDepthStencilAttachment}; args...)
	argsRef = args |> Ref
	if length(args) > 0
		# TODO
	end
	return (C_NULL |> Ref, nothing)
end

function createRenderPassFromPairs(renderPipeline; label=" Render Pass ")
	renderArgs = Dict()
	for config in renderPipeline
		renderArgs[config.first] = createEntry(config.first; config.second...) |> first
	end
	# return renderArgs
	colorAttachments = renderArgs[GPUColorAttachments]
	depthStencilAttachment = get(renderArgs, GPUDepthStencilAttachment, C_NULL |> Ref)
	a = GC.@preserve label depthStencilAttachment colorAttachments partialInit(
		WGPURenderPassDescriptor;
		label = pointer(label),
		colorAttachments = pointer(colorAttachments[]),
		colorAttachmentCount = length(colorAttachments),
		depthStencilAttachment = depthStencilAttachment[]
	) |> Ref
	return (a, colorAttachments, label, depthStencilAttachment, renderArgs)
end

struct GPUCommandBuffer
	label
	internal
	device
end

function createCommandBuffer()

end

struct GPUCommandEncoder
	label
	internal
	device
end

struct GPUComputePassEncoder
	label
	internal
	cmdEncoder
end

function createCommandEncoder(gpuDevice, label)
	labelRef = label |> Ref
	cmdEncDesc = GC.@preserve label partialInit(
				WGPUCommandEncoderDescriptor;
				label = pointer(label)
			) |> Ref
	commandEncoder = GC.@preserve label wgpuDeviceCreateCommandEncoder(
		gpuDevice.internal[],
		cmdEncDesc |> pointer_from_objref
	) |> Ref
	return GPUCommandEncoder(label, commandEncoder, gpuDevice)
end

function beginComputePass(cmdEncoder::GPUCommandEncoder; 
			label = " ", 
			timestampWrites = [])
	computePass = GC.@preserve label wgpuCommandEncoderBeginComputePass(
		cmdEncoder.internal[],
		partialInit(
			WGPUComputePassDescriptor;
			label = pointer(label)
		) |> Ref |> pointer_from_objref
	)
	GPUComputePassEncoder(label, Ref(computePass), cmdEncoder)
end

function beginRenderPass(cmdEncoder::GPUCommandEncoder, renderPipelinePairs; label = " ")
	(req, rest...) = createRenderPassFromPairs(renderPipelinePairs; label = label)
	renderPass = wgpuCommandEncoderBeginRenderPass(
		cmdEncoder.internal[],
		req |> pointer_from_objref
	) |> Ref 
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


function finish(cmdEncoder::GPUCommandEncoder; label=" ")
	cmdEncoderFinish = GC.@preserve label wgpuCommandEncoderFinish(
		cmdEncoder.internal[],
		Ref(partialInit(
			WGPUCommandBufferDescriptor;
			label = pointer(label)
		))
	)
	cmdEncoder.internal[] = C_NULL
	return GPUCommandBuffer(label, Ref(cmdEncoderFinish), cmdEncoder)
end


function destroy(cmdEncoder::GPUCommandEncoder)
	wgpuCommandEncoderDrop(cmdEncoder.internal[])
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


function endEncoder()
	
end


function destroy()

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


function setBlendeConstant()
	
end


function setStencilRefernce()
	
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


function setVertexBuffer()

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
	commandBufferListPtr = pointer(map((cmdbuf)-> cmdbuf.internal[], commandBuffers))
	wgpuQueueSubmit(queue.internal[], length(commandBuffers), commandBufferListPtr)
	foreach((cmdbuf) -> cmdbuf.internal[] = C_NULL, commandBuffers)
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
	texData = args[:textureData][]
	dataLength = length(texData)
	GC.@preserve texData wgpuQueueWriteTexture(
		queue.internal[],
		destination,
		pointer(texData),
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
	tmpBuffer = WGPU.createBuffer(" ", 
								gpuDevice, 
								size, 
								usage,
								false)
	commandEncoder =  createCommandEncoder(gpuDevice, " ")
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
	windowRef[] = window = GLFW.CreateWindow(640, 480, title)
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
	fields = fieldnames(typeof(a))
	for pair in args
		if pair.first in fields
			setproperty!(a, pair.first, pair.second)
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

function destroy(texView::GPUTexture)
	if tex.internal[] != C_NULL
		tmpTex = tex.internal[]
		tex.internal[] = C_NULL
		wgpuTextureDrop(tmpTex)
	end
end


end
