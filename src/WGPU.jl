module WGPU
export SIZE_MAX
const SIZE_MAX=256

using Reexport

include("LibWGPU.jl")
include("utils.jl")

@reexport using .LibWGPU

end # module
