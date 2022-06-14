include("canvas.jl")

mutable struct GLFWGPUCanvas <: WGPUCanvasBase
	window
	needDraw
	requestDrawTimerRunning
	changingPixelRatio
	isMinimized
	pixelRatio
	screenSizeIsLogical
	setLogicalSize
	requestDraw
end

function onPixelRatioChange(glfw::GLFWGPUCanvas, args)
	if glfw.changingPixelRatio
		return
	end
	#TODO fill other details
	glfw.changingPixelRatio = true
	glfw.requestDraw()
end

function onSizeChange(glfw::GLFWGPUCanvas, args)
	glfw.determineSize()
	glfw.requestDraw()
end

function onClose(glfw::GLFWGPUCanvas, args)
	glfw.hideWindow(glfw.window)
	glfw.handleEvent(
		# TODO fill details
	)
end


function onWindowDirty(glfw::GLFWGPUCanvas, args)
	glfw.requestDraw()
end
