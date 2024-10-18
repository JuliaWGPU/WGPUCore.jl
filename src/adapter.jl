

mutable struct GPUAdapter
    name::Any
    features::Any
    internal::Any
    limits::Any
    properties::Any
    options::Any
    supportedLimits::Any
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
    
    backendType = getDefaultBackendType()

    adapterOptions = cStruct(WGPURequestAdapterOptions)
	if (typeof(canvas) == FallbackCanvas) || (canvas === nothing)
    	adapterOptions.compatibleSurface = C_NULL
    else
    	adapterOptions.compatibleSurface = canvas.surfaceRef[]
    end
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

    infos = cStruct(WGPUAdapterInfo)

    wgpuAdapterGetInfo(adapter[], infos |> ptr)

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
        infos,
        adapterOptions,
        backendType
    )
end


