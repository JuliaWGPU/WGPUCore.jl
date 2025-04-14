abstract type AbstractWGPUCanvas end

abstract type AbstractWGPUCanvasContext end

function attachDrawFunction(canvas::AbstractWGPUCanvas, f)
    if canvas.drawFunc === nothing
        canvas.drawFunc = f
    end
end

function config(a::T; args...) where {T<:AbstractWGPUCanvasContext}
    fields = fieldnames(typeof(a))
    for pair in args
        if pair.first in fields
            setproperty!(a, pair.first, pair.second)
        else
            @error "Cannot set field $pair. Check if its a valid field for $T"
        end
    end
end

function unconfig(a::T) where {T<:AbstractWGPUCanvasContext}
    for field in fieldnames(T)
        setproperty!(a, field, defaultInit(fieldtype(T, field)))
    end
end


mutable struct FallbackCanvas <: AbstractWGPUCanvas
    title::String
    size::Tuple
    canvasContext::Any
    needDraw::Any
    requestDrawTimerRunning::Any
    changingPixelRatio::Any
    isMinimized::Bool
    device::Any
    drawFunc::Any
end

function getWindowId(canvas::FallbackCanvas)
    return nothing
end

function present(canvas::FallbackCanvas, textureView)
    return nothing
end

function getPreferredFormat(canvas::FallbackCanvas)
    return getEnum(WGPUTextureFormat, "RGBA8Unorm")
end

function getCanvas()
    defaultCanvas(FallbackCanvas)
end

function getCanvas(::Val{:FallbackCanvas})
    defaultCanvas(FallbackCanvas)
end

function defaultCanvas(::Type{FallbackCanvas})
    title = "Offscreen Window"
    canvas = FallbackCanvas(
        title,
        (500, 500),
        nothing,
        false,
        nothing,
        false,
        false,
        device,
        nothing,
    )

    return canvas
end


mutable struct GPUCanvasContextOffscreen <: AbstractWGPUCanvasContext
    canvasRef::Ref{FallbackCanvas}
    internal::Any
    device::Any
    currentTexture::Any
    currentTextureView::Any
    format::Union{Nothing, WGPUTextureFormat}
    usage::WGPUTextureUsage
    compositingAlphaMode::Any
    size::Any
    physicalSize::Any
    pixelRatio::Any
    logicalSize::Any
    surfaceSize::Any
end

function getContext(gpuCanvas::FallbackCanvas)
    if gpuCanvas.canvasContext == nothing
        gpuCanvas.canvasContext = GPUCanvasContextOffscreen(
            Ref(gpuCanvas),             # canvasRef::Ref{FallbackCanvas}
            nothing,                    # internal::Any
            gpuCanvas.device,           # device::Any
            nothing,                    # currentTexture::Any
            nothing,                    # currentTextureView::Any
            nothing,                    # format::WGPUTextureFormat
            WGPUTextureUsage_RenderAttachment, # usage::WGPUTextureUsage
            nothing,                    # compositingAlphaMode::Any
            nothing,                    # size::Any
            (500, 500),                 # physicalSize::Any
            (1, 1),                     # pixelRatio::Any
            nothing,                    # logicalSize::Any
            (-1, -1)                    # surfaceSize::Any            
        )
    end
    return gpuCanvas.canvasContext
end


function configure(
    canvasContext::GPUCanvasContextOffscreen;
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

function unconfigure(canvasContext::GPUCanvasContextOffscreen)
    canvasContext.device = nothing
    canvasContext.format = nothing
    canvasContext.usage = nothing
    canvasContext.compositingAlphaMode = nothing
    canvasContext.size = nothing
end

function determineSize(cntxt::GPUCanvasContextOffscreen)
    psize = cntxt.physicalSize
    cntxt.logicalSize = psize ./ cntxt.pixelRatio
end

function getPreferredFormat(canvasContext::GPUCanvasContextOffscreen)
    canvas = canvasCntxt.canvasRef[]
    if canvas !== nothing
        return getPreferredFormat(canvas)
    end
    return getEnum(WGPUTextureFormat, "RGBA8Unorm")
end

function getCurrentTexture(cntxt::GPUCanvasContextOffscreen)
    createNewTextureMaybe(cntxt)
    return cntxt.currentTextureView
end

function present(cntxt::GPUCanvasContextOffscreen)
    if cntxt.currentTexture != nothing && cntxt.currentTexture.internal[] != C_NULL
        canvas = cntxt.canvasRef[]
        return present(canvas, cntxt.currentTextureView)
    end
end

function createNewTextureMaybe(canvasCntxt::GPUCanvasContextOffscreen)
    canvas = canvasCntxt.canvasRef[]
    pSize = canvasCntxt.physicalSize
    if pSize == canvasCntxt.surfaceSize
        return
    end
    canvasCntxt.surfaceSize = pSize
    canvasCntxt.currentTexture = WGPUCore.createTexture(
        canvasCntxt.device,
        "textureOffline",
        (pSize..., 1),
        1,
        1,
        getEnum(WGPUTextureDimension, "2D"),
        canvasCntxt.format,
        (canvasCntxt.usage | WGPUTextureUsage_CopySrc) |> WGPUTextureUsage,
    )
    canvasCntxt.currentTextureView = WGPUCore.createView(canvasCntxt.currentTexture)
end

function destroyWindow(canvas::FallbackCanvas)
    return nothing
end


# function getWindowId(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "getWindowId is not defined for this canvas of type $(typeof(canvas))."
# end

# function getDisplayId(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "getDisplayId is not defined for this canvas of type $(typeof(canvas))."
# end

# function getPhysicalSize(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "getPhysicalSize is not defined for this canvas of type $(typeof(canvas))"
# end

# function getContext(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "getContext is not defined for this canvas of type $(typeof(canvas))"
# end

# function drawFrame(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "Needs implementation"
# end

# function requestDraw(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "Needs implementation"
# end

# function drawFrameAndPresent(canvas::T) where {T<:AbstractWGPUCanvas}
#     setproperty!(canvas, :lastDrawTime, time())
#     drawFrame(canvas)
#     present(canvas, getContext(canvas))
# end

# function getDrawWaitTime(canvas::T) where {T<:AbstractWGPUCanvas}
#     now = time()
#     targetTime = getproperty(canvas, :lastDrawTime) + 1.0 / (getproperty(canvas, :maxFPS))
#     return max(0, targetTime - now)
# end

# function getPixelRatio(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "Not implemented error"
# end

# function getLogicalSize(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "Not implemented error"
# end

# function getPhysicalSize(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "Not implemented error"
# end

# function close(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "Not implemented error"
# end

# function isClose(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "Not implemented error"
# end

# function requestDraw(canvas::T) where {T<:AbstractWGPUCanvas}
#     @error "Not implemented error"
# end
