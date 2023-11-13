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
