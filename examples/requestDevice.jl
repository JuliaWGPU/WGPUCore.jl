using WGPUCore
using Debugger
include("$(pkgdir(WGPUCore))/examples/requestAdapter.jl")
# include("$(pkgdir(WGPUCore))/src/queue.jl")
# include("$(pkgdir(WGPUCore))/src/device.jl")

device = WGPUCore.requestDevice(adapter)