## Load WGPU
using WGPU
using Test

using WGPUNative

flatten(x) = reshape(x, (:,))

vertexData =  cat([
       [-1, -1, 1, 1, 0, 0],
       [1, -1, 1, 1, 1, 0],
       [1, 1, 1, 1, 1, 1],
       [-1, 1, 1, 1, 0, 1],
       [-1, 1, -1, 1, 1, 0],
       [1, 1, -1, 1, 0, 0],
       [1, -1, -1, 1, 0, 1],
       [-1, -1, -1, 1, 1, 1],
       [1, -1, -1, 1, 0, 0],
       [1, 1, -1, 1, 1, 0],
       [1, 1, 1, 1, 1, 1],
       [1, -1, 1, 1, 0, 1],
       [-1, -1, 1, 1, 1, 0],
       [-1, 1, 1, 1, 0, 0],
       [-1, 1, -1, 1, 0, 1],
       [-1, -1, -1, 1, 1, 1],
       [1, 1, -1, 1, 1, 0],
       [-1, 1, -1, 1, 0, 0],
       [-1, 1, 1, 1, 0, 1],
       [1, 1, 1, 1, 1, 1],
       [1, -1, 1, 1, 0, 0],
       [-1, -1, 1, 1, 1, 0],
       [-1, -1, -1, 1, 1, 1],
       [1, -1, -1, 1, 0, 1],
   ]..., dims=2) .|>  Float32

canvas = WGPU.defaultInit(WGPU.WGPUCanvas)
gpuDevice = WGPU.getDefaultDevice()

(vertexBuffer, tmpData) = WGPU.createBufferWithData(
	gpuDevice, 
	"buffer1", 
	vertexData, 
	["Storage", "CopyDst", "CopySrc"]
)

Test.@test reshape(tmpData[], (6, 24)) == vertexData

function fill_columns(x::Vector{T}, outSize; fill=nothing) where T
	@assert (length(x) == reduce(*, outSize) && fill==nothing) "Dimension do not match; set 'fill' to create an array anyways."
	out = Array{T, 2}(undef, outSize)
	for idx in 1:last(outSize)
		offset = (idx - 1)*(first(outSize)) + 1
		len = offset+first(outSize) -1
		out[:, idx] .= x[offset: len ]
	end
	out
end

dataDown = reinterpret(Float32, WGPU.readBuffer(gpuDevice, vertexBuffer, 0, sizeof(vertexData))) |> collect

dataDown2 = reshape(dataDown, (6, 24))

Test.@test reshape(vertexData, (6, 24)) == dataDown2

GC.gc()

# gpuDevice = nothing
