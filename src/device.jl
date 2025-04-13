export requestDevice, device

device = Ref{WGPUDevice}()

function getDeviceCallback(device::Ref{WGPUDevice})
    function request_device_callback(
        status::WGPURequestDeviceStatus,
        returnDevice::WGPUDevice,
        message::WGPUStringView,
        userData::Ptr{Cvoid},
    )
        if status == WGPURequestDeviceStatus_Success
            device[] = returnDevice
        elseif message != C_NULL
            @warn unsafe_string(message.data, message.length)
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
        tracePath = toWGPUString(tracepath),
    )

    wgpuRequiredLimits =
        cStruct(WGPULimits; nextInChain = C_NULL)

    wgpuQueueDescriptor = cStruct(
        WGPUQueueDescriptor;
        nextInChain = C_NULL,
        label = toWGPUString("DEFAULT QUEUE"),
    ) 

    wgpuDeviceDescriptor =
        cStruct(
            WGPUDeviceDescriptor;
            label = toWGPUString(label),
            nextInChain = convert(Ptr{WGPUChainedStruct}, deviceExtras |> ptr),
            requiredFeatureCount = 0,
            requiredLimits = (wgpuRequiredLimits |> ptr),
            defaultQueue = wgpuQueueDescriptor |> concrete,
        )

    requestDeviceCallback = @cfunction(
        getDeviceCallback(device),
        Cvoid,
        (WGPURequestDeviceStatus, WGPUDevice, WGPUStringView, Ptr{Cvoid})
    )

    deviceCBInfo = WGPURequestDeviceCallbackInfo |> CStruct 
    deviceCBInfo.nextInChain = C_NULL
    deviceCBInfo.callback = requestDeviceCallback
    deviceCBInfo.userdata1 = device[]

    # TODO dump all the info to a string or add it to the GPUAdapter structure
    # if device[] == C_NULL
        wgpuAdapterRequestDevice(
            gpuAdapter.internal[],
            C_NULL,
            deviceCBInfo |> concrete,
        )
    # end

    supportedLimits = cStruct(WGPULimits;)


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
        nothing,
        supportedLimits,
        backendType,
    )
end

function getDefaultDevice(canvas; backendType = getDefaultBackendType())
    adapter = WGPUCore.requestAdapter(;canvas=canvas)
    device = requestDevice(adapter)
    if canvas != nothing
        canvas.device = device
    end
    return device
end
