using GLFW

mutable struct MouseState
    leftButton::Any
    rightButton::Any
    middleButton::Any
    scroll::Any
end

initMouse(::Type{MouseState}) = begin
    MouseState(false, false, false, false)
end

function setJoystickCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (joystick, event) -> println("$joystick $event")
    else
        callback = f
    end
    GLFW.SetJoystickCallback(callback)
end

function setMonitorCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (monitor, event) -> println("$monitor $event")
    else
        callback = f
    end
    GLFW.SetMonitorCallback(callback)
end

function setWindowCloseCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (event) -> println("Window closed")
    else
        callback = f
    end
    GLFW.SetWindowCloseCallback(canvas.windowRef[], callback)
end

function setWindowPosCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, x, y) -> println("window position : $x $y")
    else
        callback = f
    end
    GLFW.SetWindowPosCallback(canvas.windowRef[], callback)
end

function setWindowSizeCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, w, h) -> begin
            println("window size : $w $h")
            canvas.size = (w, h)
            determineSize(canvas.context)
        end
    else
        callback = f
    end
    GLFW.SetWindowSizeCallback(canvas.windowRef[], callback)
end

function setWindowFocusCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, focused) -> println("window focus : $focused")
    else
        callback = f
    end
    GLFW.SetWindowFocusCallback(canvas.windowRef[], callback)
end

function setWindowIconifyCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, iconified) -> println("window iconify : $iconified")
    else
        callback = f
    end
    GLFW.SetWindowIconifyCallback(canvas.windowRef[], callback)
end

function setWindowMaximizeCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, maximized) -> println("window maximized : $maximized")
    else
        callback = f
    end
    GLFW.SetWindowMaximizeCallback(canvas.windowRef[], callback)
end

function setKeyCallback(canvas::AbstractWGPUCanvas, f = nothing)
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


function setCharModsCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, c, mods) -> println("char: $c, mods : $mods")
    else
        callback = f
    end
    GLFW.SetCharModsCallback(canvas.windowRef[], callback)
end

function setMouseButtonCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (win, button, action, mods) -> begin
            println("$button : $action : $mods")
        end
    else
        callback = f
    end
    GLFW.SetMouseButtonCallback(canvas.windowRef[], callback)
end

function setCursorPosCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, x, y) -> println("cursor $x : $y")
    else
        callback = f
    end
    GLFW.SetCursorPosCallback(canvas.windowRef[], callback)
end

function setScrollCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, xoff, yoff) -> println("scroll $xoff : $yoff")
    else
        callback = f
    end
    GLFW.SetScrollCallback(canvas.windowRef[], callback)
end

function setDropCallback(canvas::AbstractWGPUCanvas, f = nothing)
    if f == nothing
        callback = (_, paths) -> println("path $paths")
    else
        callback = f
    end
    GLFW.SetDropCallback(canvas.windowRef[], callback)
end
