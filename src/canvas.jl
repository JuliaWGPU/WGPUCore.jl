abstract type AbstractCanvasInterface end

function getWindowId(canvas::T) where {T<:AbstractCanvasInterface}
    @error "getWindowId is not defined for this canvas of type $(typeof(canvas))."
end

function getDisplayId(canvas::T) where {T<:AbstractCanvasInterface}
    @error "getDisplayId is not defined for this canvas of type $(typeof(canvas))."
end

function getPhysicalSize(canvas::T) where {T<:AbstractCanvasInterface}
    @error "getPhysicalSize is not defined for this canvas of type $(typeof(canvas))"
end

function getContext(canvas::T) where {T<:AbstractCanvasInterface}
    @error "getContext is not defined for this canvas of type $(typeof(canvas))"
end

abstract type WGPUCanvasBase <: AbstractCanvasInterface end

function drawFrame(canvas::T) where {T<:WGPUCanvasBase}
    @error "Needs implementation"
end

function requestDraw(canvas::T) where {T<:WGPUCanvasBase}
    @error "Needs implementation"
end

function drawFrameAndPresent(canvas::T) where {T<:WGPUCanvasBase}
    setproperty!(canvas, :lastDrawTime, time())
    drawFrame(canvas)
    present(canvas, getContext(canvas))
end

function getDrawWaitTime(canvas::T) where {T<:WGPUCanvasBase}
    now = time()
    targetTime = getproperty(canvas, :lastDrawTime) + 1.0 / (getproperty(canvas, :maxFPS))
    return max(0, targetTime - now)
end

function getPixelRatio(canvas::T) where {T<:WGPUCanvasBase}
    @error "Not implemented error"
end

function getLogicalSize(canvas::T) where {T<:WGPUCanvasBase}
    @error "Not implemented error"
end


function getPhysicalSize(canvas::T) where {T<:WGPUCanvasBase}
    @error "Not implemented error"
end

function close(canvas::T) where {T<:WGPUCanvasBase}
    @error "Not implemented error"
end

function isClose(canvas::T) where {T<:WGPUCanvasBase}
    @error "Not implemented error"
end


function requestDraw(canvas::T) where {T<:WGPUCanvasBase}
    @error "Not implemented error"
end


mutable struct WGPUAutoGUI
    lastEventTime::Any
    pendingEvents::Any
    eventHandlers::Any
end


function getEventWaitTime(gui::WGPUAutoGUI)
    rate = 75
    now = time()
    targetTime = gui.lastEventTime + 1.0 / rate
    return max(0, targetTime - now)
end

function handleEventRateLimited(gui::WGPUAutoGUI, ev, callLaterFunc, matchKeys, accumKeys)

end


function dispatchPendingEvents(gui::WGPUAutoGUI)

end


function dispatchEvent(gui::WGPUAutoGUI, event)

end

function handleEvent(gui::WGPUAutoGUI, event)
    dispatchPendingEvent(gui)
    dispatchEvent(event)
end


function addEventHandler(gui::WGPUAutoGUI, args)

end


function removeEventHandler(gui::WGPUAutoGUI, types)

end

function getCanvas()
    
end