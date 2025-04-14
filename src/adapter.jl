

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
        message::WGPUStringView,
        userData::Ptr{Cvoid},
    )
        global adapter
        # @debug status
        if status == WGPURequestAdapterStatus_Success
            adapter[] = returnAdapter
        elseif message != C_NULL
            @error unsafe_string(message.data, message.length)
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
        (WGPURequestAdapterStatus, WGPUAdapter, WGPUStringView, Ptr{Cvoid})
    )

    callbackInfo = WGPURequestAdapterCallbackInfo |> CStruct
    callbackInfo.nextInChain = C_NULL
    callbackInfo.userdata1 = adapter[]
    callbackInfo.callback = requestAdapterCallback

    ## request adapter 
    instance = getWGPUInstance()
    
    wgpuInstanceRequestAdapter(
        instance[], 
        C_NULL, 
        callbackInfo |> concrete,
    )

    @assert adapter[] != C_NULL

    infos = cStruct(WGPUAdapterInfo)

    wgpuAdapterGetInfo(adapter[], infos |> ptr)

    nativeLimits = WGPUNativeLimits |> CStruct

    supportedLimits = cStruct(WGPULimits)
    supportedLimits.nextInChain = nativeLimits.chain.next

    wgpuAdapterGetLimits(adapter[], supportedLimits |> ptr)

    features = []
    GPUAdapter(
        "WGPU",
        features,
        adapter,
        nativeLimits,
        supportedLimits,
        infos,
        adapterOptions,
        backendType
    )
end


