using GLFW_jll
using GLFW
# 
function GetX11Window(w::GLFW.Window)
    ptr = ccall((:glfwGetX11Window, libglfw), GLFW.Window, (GLFW.Window,), w)
    return ptr
end
# 
function GetX11Display()
    ptr = ccall((:glfwGetX11Display, libglfw), Ptr{GLFW.Window}, ())
    return ptr
end


mutable struct LinuxCanvas <: AbstractWGPUCanvas
    title::String
    size::Tuple
    displayRef::Any
    windowRef::Any
    windowX11Ref::Any
    surfaceRef::Any
    surfaceDescriptorRef::Any
    xlibSurfaceRef::Any
    needDraw::Any
    requestDrawTimerRunning::Any
    changingPixelRatio::Any
    isMinimized::Bool
    device::Any
    context::Any
    drawFunc::Any
    mouseState::Any
end


function defaultCanvas(::Type{LinuxCanvas}; windowSize = (500, 500))
	displayRef = Ref{Ptr{GLFW.Window}}()
	windowRef = Ref{GLFW.Window}()
    windowX11Ref = Ref{GLFW.Window}()
    surfaceRef = Ref{WGPUSurface}()
    title = "GLFW WGPU Window"
    displayRef[] = GetX11Display()
    GLFW.Init()
    GLFW.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
    windowRef[] = window = GLFW.CreateWindow(windowSize..., title)
	windowX11Ref[] = GetX11Window(window)
	chain = cStruct(
	    WGPUChainedStruct;
	    next = C_NULL,
	    sType = WGPUSType_SurfaceDescriptorFromXlibWindow,
	)
    xlibSurfaceRef =
        cStruct(
            WGPUSurfaceDescriptorFromXlibWindow;
			chain = chain |> concrete,
            display = displayRef[],
            window = windowX11Ref[].handle,
        )
    surfaceDescriptorRef = cStruct(
        WGPUSurfaceDescriptor;
        label = C_NULL,
        nextInChain = xlibSurfaceRef |> ptr,
    )
    instance = getWGPUInstance()
    surfaceRef[] =
        wgpuInstanceCreateSurface(instance[], surfaceDescriptorRef |> ptr)
    title = "GLFW Window"
    canvas = LinuxCanvas(
        title,
        windowSize,
        displayRef,
        windowRef,
        windowX11Ref,
        surfaceRef,
        surfaceDescriptorRef,
        xlibSurfaceRef,
        false,
        nothing,
        false,
        false,
        device,
        nothing,
        nothing,
        defaultInit(MouseState),
    )
    getContext(canvas)
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


mutable struct GPUCanvasContext
    canvasRef::Ref{LinuxCanvas}
    surfaceSize::Any
    surfaceId::Any
    internal::Any
    currentTexture::Any
    device::Any
    format::WGPUTextureFormat
    usage::WGPUTextureUsage
    compositingAlphaMode::Any
    size::Any
    physicalSize::Any
    pixelRatio::Any
    logicalSize::Any
end

function getContext(gpuCanvas::LinuxCanvas)
    if gpuCanvas.context == nothing
        context = GPUCanvasContext(
            Ref(gpuCanvas),
            (-1, -1),
            gpuCanvas.surfaceRef[],
            nothing,
            nothing,
            gpuCanvas.device,
            WGPUTextureFormat_R8Unorm,
            WGPUTextureUsage(0),
            nothing,
            nothing,
            gpuCanvas.size,
            nothing,
            nothing
        )
        gpuCanvas.context = context
    else
        return gpuCanvas.context
    end
end

function configure(
    canvasContext::GPUCanvasContext;
    device,
    format,
    usage,
    viewFormats,
    compositingAlphaMode,
    size,
)
    unconfig(canvasContext)
    canvasContext.device = device
    canvasContext.format = format
    canvasContext.usage = usage
    canvasContext.compositingAlphaMode = compositingAlphaMode
    canvasContext.size = size
end

function unconfigure(canvasContext::GPUCanvasContext)
    canvasContext.device = nothing
    canvasContext.format = nothing
    canvasContext.usage = nothing
    canvasContext.compositingAlphaMode = nothing
    canvasContext.size = nothing
end

function determineSize(cntxt::GPUCanvasContext)
    pixelRatio = GLFW.GetWindowContentScale(cntxt.canvasRef[].windowRef[]) |> first
    psize = GLFW.GetFramebufferSize(cntxt.canvasRef[].windowRef[])
    cntxt.pixelRatio = pixelRatio
    cntxt.physicalSize = (psize.width, psize.height)
    cntxt.logicalSize = (psize.width, psize.height) ./ pixelRatio
    # TODO skipping event handlers for now
end


function getPreferredFormat(canvas::LinuxCanvas)
    return getEnum(WGPUTextureFormat, "BGRA8Unorm")
end

function getPreferredFormat(canvasContext::GPUCanvasContext)
    canvas = canvasCntxt.canvasRef[]
    if canvas != nothing
        return getPreferredFormat(canvas)
    end
    return getEnum(WGPUTextureFormat, "RGBA8Unorm")
end

function getSurfaceIdFromCanvas(cntxt::GPUCanvasContext)
    # TODO return cntxt
end

function getCurrentTexture(cntxt::GPUCanvasContext)
	# TODO this expensive so commenting it. Only first run though
    # if cntxt.device.internal[] == C_NULL
        # @error "context must be configured before request for texture"
    # end
    if cntxt.currentTexture == nothing
        createNativeSwapChainMaybe(cntxt)
        id = wgpuSwapChainGetCurrentTextureView(cntxt.internal[]) |> Ref
        size = (cntxt.surfaceSize..., 1)
        cntxt.currentTexture =
            GPUTextureView("swap chain", id, cntxt.device, nothing, size, nothing |> Ref)
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
    swapChain =
        cStruct(
            WGPUSwapChainDescriptor;
            usage = canvasCntxt.usage,
            format = canvasCntxt.format,
            width = max(1, pSize[1]),
            height = max(1, pSize[2]),
            presentMode = presentMode,
        )
    if canvasCntxt.surfaceId == nothing
        canvasCntxt.surfaceId = getSurfaceIdFromCanvas(canvas)
    end
    canvasCntxt.internal =
        wgpuDeviceCreateSwapChain(
            canvasCntxt.device.internal[],
            canvasCntxt.surfaceId,
            swapChain |> ptr,
        ) |> Ref
end

function destroyWindow(canvas::LinuxCanvas)
    GLFW.DestroyWindow(canvas.windowRef[])
end

