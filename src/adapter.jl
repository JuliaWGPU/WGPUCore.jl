

mutable struct GPUAdapter
    name::Any
    features::Any
    internal::Any
    limits::Any
    properties::Any
    options::Any
    supportedLimits::Any
    extras::Any
    backendType::WGPUBackendType
end

function getAdapterCallback(adapter::Ref{WGPUAdapter})
    function request_adapter_callback(
        status::WGPURequestAdapterStatus,
        returnAdapter::WGPUAdapter,
        message::Ptr{Cchar},
        userData::Ptr{Cvoid},
    )
        global adapter
        # @debug status
        if status == WGPURequestAdapterStatus_Success
            adapter[] = returnAdapter
        elseif message != C_NULL
            @error unsafe_string(message)
        end
        return nothing
    end
    return request_adapter_callback
end

adapter = Ref{WGPUAdapter}()

function requestAdapter(;
    canvas = nothing,
    powerPreference = WGPUPowerPreference_HighPerformance,
)
    chain = cStruct(
        WGPUChainedStruct;
        sType = WGPUSType(Int64(WGPUSType_AdapterExtras)),
    )
    
    backendType = getDefaultBackendType()

    extras = cStruct(
        WGPUAdapterExtras;
        backend=backendType,
        chain = chain |> concrete
    )

    adapterOptions = cStruct(WGPURequestAdapterOptions)
    adapterOptions.compatibleSurface = C_NULL
    adapterOptions.nextInChain = rawCast(WGPUChainedStruct, extras)
    adapterOptions.powerPreference = powerPreference
    adapterOptions.forceFallbackAdapter = false
    
    requestAdapterCallback = @cfunction(
        getAdapterCallback(adapter),
        Cvoid,
        (WGPURequestAdapterStatus, WGPUAdapter, Ptr{Cchar}, Ptr{Cvoid})
    )

    ## request adapter 
    instance = getWGPUInstance()
    
    wgpuInstanceRequestAdapter(
        instance[], 
        adapterOptions |> ptr, 
        requestAdapterCallback,
        C_NULL
    )

    @assert adapter[] != C_NULL

    properties = cStruct(WGPUAdapterProperties)

    wgpuAdapterGetProperties(adapter[], properties |> ptr)

    supportedLimits = cStruct(WGPUSupportedLimits)
    cLimits = supportedLimits.limits

    wgpuAdapterGetLimits(adapter[], supportedLimits |> ptr)

    features = []
    GPUAdapter(
        "WGPU",
        features,
        adapter,
        cLimits,
        supportedLimits,
        properties,
        adapterOptions,
        extras,
        backendType
    )
end


