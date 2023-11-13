using GLFW_jll
using GLFW

using WGPUCore

using Pkg.Artifacts

artifact_toml = joinpath(@__DIR__, "..", "Artifacts.toml")

cocoa_hash = artifact_hash("Cocoa", artifact_toml)

cocoalibpath = artifact_path(cocoa_hash)

function GetCocoaWindow(window::GLFW.Window)
	ccall((:glfwGetCocoaWindow, libglfw), Ptr{Nothing}, (Ptr{GLFW.Window},), window.handle)
end

const libcocoa = joinpath(cocoalibpath, "cocoa")

function getMetalLayer()
    ccall((:getMetalLayer, libcocoa), Ptr{UInt8}, ())
end

function wantLayer(nswindow)
    ccall((:wantLayer, libcocoa), Cvoid, (Ptr{Nothing},), nswindow)
end

function setMetalLayer(nswindow, metalLayer)
    ccall(
        (:setMetalLayer, libcocoa),
        Cvoid,
        (Ptr{Nothing}, Ptr{Nothing}),
        nswindow,
        metalLayer,
    )
end

mutable struct GLFWMacCanvas <: GLFWCanvas
    title::String
    size::Tuple
    windowRef::Any # This has to be platform specific may be
    surfaceRef::Any
    surfaceDescriptorRef::Any
    metalSurfaceRef::Any
    nsWindow::Any
    metalLayer::Any
    needDraw::Any
    requestDrawTimerRunning::Any
    changingPixelRatio::Any
    isMinimized::Bool
    device::Union{GPUDevice, Nothing}
    context::Any
    drawFunc::Any
    mouseState::Any
end


function defaultCanvas(::Type{GLFWMacCanvas}; size = (500, 500))
    windowRef = Ref{GLFW.Window}()
    surfaceRef = Ref{WGPUSurface}()
    title = "GLFW WGPU Window"
    GLFW.Init()
    GLFW.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
    windowRef[] = window = GLFW.CreateWindow(size..., title)
    nswindow = GetCocoaWindow(windowRef[]) |> Ref
    metalLayer = getMetalLayer() |> Ref
    wantLayer(nswindow[])
    setMetalLayer(nswindow[], metalLayer[])
    metalSurfaceRef =
        cStruct(
            WGPUSurfaceDescriptorFromMetalLayer;
            chain = cStruct(
                WGPUChainedStruct;
                next = C_NULL,
                sType = WGPUSType_SurfaceDescriptorFromMetalLayer,
            ) |> concrete,
            layer = metalLayer[],
        )
    surfaceDescriptorRef = cStruct(
        WGPUSurfaceDescriptor;
        label = C_NULL,
        nextInChain = metalSurfaceRef |> ptr,
    )
    instance = getWGPUInstance()
    surfaceRef[] =
        wgpuInstanceCreateSurface(instance[], surfaceDescriptorRef |> ptr)
    title = "GLFW Window"
    canvas = GLFWMacCanvas(
        title,
        size,
        windowRef,
        surfaceRef,
        surfaceDescriptorRef,
        metalSurfaceRef,
        nswindow,
        metalLayer,
        false,
        nothing,
        false,
        false,
        nothing,
        nothing,
        nothing,
        initMouse(MouseState),
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
    canvasRef::Ref{GLFWMacCanvas}
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

            # canvasRef = Ref(gpuCanvas),
            # surfaceSize = (-1, -1),
            # surfaceId = gpuCanvas.surfaceRef[],
            # internal = nothing,
            # device = gpuCanvas.device,
            # physicalSize = gpuCanvas.size,
            # compositingAlphaMode = nothing,


function getContext(gpuCanvas::GLFWMacCanvas)
    if gpuCanvas.context == nothing
        context = GPUCanvasContext(
			Ref(gpuCanvas),		    	# canvasRef::Ref{GLFWMacCanvas}
			(-1, -1),			    	# surfaceSize::Any
			gpuCanvas.surfaceRef[],	    # surfaceId::Any
			nothing,				    # internal::Any
			nothing,				    # currentTexture::Any
			gpuCanvas.device,		    # device::Any
			WGPUTextureFormat(0),		# format::WGPUTextureFormat
			WGPUTextureUsage(0),		# usage::WGPUTextureUsage
			nothing,				    # compositingAlphaMode::Any
			nothing,				    # size::Any
			gpuCanvas.size,			    # physicalSize::Any
			nothing,	    			# pixelRatio::Any
			nothing,				    # logicalSize::Any
        )
        gpuCanvas.context = context
    else
        return gpuCanvas.context
    end
end


function config(a::T; args...) where {T}
    fields = fieldnames(typeof(a))
    for pair in args
        if pair.first in fields
            setproperty!(a, pair.first, pair.second)
        else
            @error "Cannot set field $pair. Check if its a valid field for $T"
        end
    end
end

function unconfig(a::T) where {T}
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


function getPreferredFormat(canvas::GLFWMacCanvas)
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

function destroyWindow(canvas::GLFWMacCanvas)
    GLFW.DestroyWindow(canvas.windowRef[])
end

