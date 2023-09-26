abstract type GLFWCanvas end

using GLFW_jll
using GLFW
using GLFW: libglfw

using WGPUCore


function GetWin32Window(window)
    ccall((:glfwGetWin32Window, libglfw), Ptr{Nothing}, (Ptr{GLFW.Window},), window.handle)
end

mutable struct MouseState
    leftButton::Any
    rightButton::Any
    middleButton::Any
    scroll::Any
end

initMouse(::Type{MouseState}) = begin
    MouseState(false, false, false, false)
end

mutable struct GLFWWindowsCanvas <: GLFWCanvas
    title::String
    size::Tuple
    windowRef::Any # This has to be platform specific may be
    surfaceRef::Any
    surfaceDescriptorRef::Any
    needDraw::Any
    requestDrawTimerRunning::Any
    changingPixelRatio::Any
    isMinimized::Bool
    device::Any
    context::Any
    drawFunc::Any
    mouseState::Any
end

function attachDrawFunction(canvas::GLFWCanvas, f)
    if canvas.drawFunc == nothing
        canvas.drawFunc = f
    end
end

function GetModuleHandle(ptr)
    ccall((:GetModuleHandleA, "kernel32"), stdcall, Ptr{UInt32}, (UInt32,), ptr)
end


function defaultCanvas(::Type{GLFWWindowsCanvas}; size = (500, 500))
    windowRef = Ref{GLFW.Window}()
    surfaceRef = Ref{WGPUSurface}()
    title = "GLFW WIN32 Window"
    GLFW.Init()
    GLFW.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
    windowRef[] = window = GLFW.CreateWindow(size..., title)
    winHandleRef = GetWin32Window(windowRef[]) |> Ref
    hinstance = GetModuleHandle(C_NULL)
    winSurfaceRef =
        cStruct(
            WGPUSurfaceDescriptorFromWindowsHWND;
            chain = cStruct(
                WGPUChainedStruct;
                next = C_NULL,
                sType = WGPUSType_SurfaceDescriptorFromWindowsHWND,
            ) |> concrete,
            hinstance = hinstance,
            hwnd = winHandleRef[]
        )
    surfaceDescriptorRef = cStruct(
        WGPUSurfaceDescriptor;
        label = C_NULL,
        nextInChain = winSurfaceRef |> ptr,
    )
    instance = getWGPUInstance()
    surfaceRef[] =
        wgpuInstanceCreateSurface(instance, surfaceDescriptorRef |> ptr)
    title = "GLFW Window"
    canvas = GLFWWindowsCanvas(
        title,
        size,
        windowRef,
        surfaceRef,
        surfaceDescriptorRef,
        false,
        nothing,
        false,
        false,
        backend.device,
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

function setJoystickCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (joystick, event) -> println("$joystick $event")
    else
        callback = f
    end
    GLFW.SetJoystickCallback(callback)
end

function setMonitorCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (monitor, event) -> println("$monitor $event")
    else
        callback = f
    end
    GLFW.SetMonitorCallback(callback)
end

function setWindowCloseCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (event) -> println("Window closed")
    else
        callback = f
    end
    GLFW.SetWindowCloseCallback(canvas.windowRef[], callback)
end

function setWindowPosCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, x, y) -> println("window position : $x $y")
    else
        callback = f
    end
    GLFW.SetWindowPosCallback(canvas.windowRef[], callback)
end

function setWindowSizeCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, w, h) -> begin
            println("window size : $w $h")
            canvas.size = (w, h)
            determineSize(canvas.context[])
        end
    else
        callback = f
    end
    GLFW.SetWindowSizeCallback(canvas.windowRef[], callback)
end

function setWindowFocusCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, focused) -> println("window focus : $focused")
    else
        callback = f
    end
    GLFW.SetWindowFocusCallback(canvas.windowRef[], callback)
end

function setWindowIconifyCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, iconified) -> println("window iconify : $iconified")
    else
        callback = f
    end
    GLFW.SetWindowIconifyCallback(canvas.windowRef[], callback)
end

function setWindowMaximizeCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, maximized) -> println("window maximized : $maximized")
    else
        callback = f
    end
    GLFW.SetWindowMaximizeCallback(canvas.windowRef[], callback)
end

function setKeyCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback =
            (_, key, scancode, action, mods) -> begin
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


function setCharModsCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, c, mods) -> println("char: $c, mods : $mods")
    else
        callback = f
    end
    GLFW.SetCharModsCallback(canvas.windowRef[], callback)
end

function setMouseButtonCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (win, button, action, mods) -> begin
            println("$button : $action : $mods")
        end
    else
        callback = f
    end
    GLFW.SetMouseButtonCallback(canvas.windowRef[], callback)
end

function setCursorPosCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, x, y) -> println("cursor $x : $y")
    else
        callback = f
    end
    GLFW.SetCursorPosCallback(canvas.windowRef[], callback)
end

function setScrollCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, xoff, yoff) -> println("scroll $xoff : $yoff")
    else
        callback = f
    end
    GLFW.SetScrollCallback(canvas.windowRef[], callback)
end

function setDropCallback(canvas::GLFWCanvas, f = nothing)
    if f == nothing
        callback = (_, paths) -> println("path $paths")
    else
        callback = f
    end
    GLFW.SetDropCallback(canvas.windowRef[], callback)
end


mutable struct GPUCanvasContext
    canvasRef::Ref{GLFWWindowsCanvas}
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

function getContext(gpuCanvas::GLFWWindowsCanvas)
    if gpuCanvas.context == nothing
        context = partialInit(
            GPUCanvasContext;
            canvasRef = Ref(gpuCanvas),
            surfaceSize = (-1, -1),
            surfaceId = gpuCanvas.surfaceRef[],
            internal = nothing,
            device = gpuCanvas.device,
            physicalSize = gpuCanvas.size,
            compositingAlphaMode = nothing,
        )
        gpuCanvas.context = context
    else
        return gpuCanvas.context
    end
end


function config(a::T; args...) where {T}
    fields = fieldnames(typeof(a[]))
    for pair in args
        if pair.first in fields
            setproperty!(a[], pair.first, pair.second)
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
    cntxt.physicalSize = psize
    cntxt.logicalSize = (psize.width, psize.height) ./ pixelRatio
    # TODO skipping event handlers for now
end


function getPreferredFormat(canvas::GLFWWindowsCanvas)
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
    if cntxt.device.internal[] == C_NULL
        @error "context must be configured before request for texture"
        return
    end
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

function destroyWindow(canvas::GLFWWindowsCanvas)
    GLFW.DestroyWindow(canvas.windowRef[])
end

const WGPUCanvas = GLFWWindowsCanvas
