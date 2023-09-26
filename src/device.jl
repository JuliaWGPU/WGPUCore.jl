export requestDevice, device

device = Ref{WGPUDevice}()

function getDeviceCallback(device::Ref{WGPUDevice})
    function request_device_callback(
        status::WGPURequestDeviceStatus,
        returnDevice::WGPUDevice,
        message::Ptr{Cchar},
        userData::Ptr{Cvoid},
    )
        if status == WGPURequestDeviceStatus_Success
            device[] = returnDevice
        elseif message != C_NULL
            @warn unsafe_string(message)
        end
        return nothing
    end
    return request_device_callback
end



mutable struct GPUDevice
    label::Any
    internal::Any
    adapter::Any
    features::Any
    queue::Any
    queueDescriptor::Any
    deviceDescriptor::Any
    requiredLimits::Any
    wgpuLimits::Any
    backendType::Any
    supportedLimits::Any
end

# wgpuAdapterRequestDevice(
#     adapter[],
#     C_NULL,
#     requestDeviceCallback,
#     device[]
# )

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
        chain = chainObj |> concrete,
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
            defaultQueue = wgpuQueueDescriptor |> concrete,
        )

    requestDeviceCallback = @cfunction(
        getDeviceCallback(device),
        Cvoid,
        (WGPURequestDeviceStatus, WGPUDevice, Ptr{Cchar}, Ptr{Cvoid})
    )
    # TODO dump all the info to a string or add it to the GPUAdapter structure
    # if device[] == C_NULL
        wgpuAdapterRequestDevice(
            gpuAdapter.internal[],
            C_NULL,
            requestDeviceCallback,
            device[],
        )
    # end

    supportedLimits = cStruct(WGPUSupportedLimits;)

    wgpuDeviceGetLimits(device[], supportedLimits |> ptr)
    features = []
    deviceQueue = Ref(wgpuDeviceGetQueue(device[]))
    queue = GPUQueue(" GPU QUEUE ", deviceQueue, nothing)
    backendType = gpuAdapter.backendType # TODO this needs to be current backend
    GPUDevice(
        "WGPU Device",
        device,
        gpuAdapter,
        features,
        queue,
        wgpuQueueDescriptor,
        wgpuDeviceDescriptor,
        wgpuRequiredLimits,
        wgpuLimits,
        supportedLimits,
        backendType,
    )
end

function getDefaultDevice(; backendType = getDefaultBackendType())
    adapter = WGPUCore.requestAdapter()
    device = requestDevice(adapter)
    return device
end
