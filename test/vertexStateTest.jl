GC.gc(true)

using WGPUCore
using Test

vertexStateOptions = [
    :_module => C_NULL,
    :entryPoint => "vs_main",
    :buffers => [
        WGPUCore.GPUVertexBufferLayout => [
            :arrayStride => 4 * 6,
            :stepMode => "Vertex",
            :attributes => [
                :attribute => [:format => "Float32x4", :offset => 0, :shaderLocation => 0],
                :attribute => [
                    :format => "Float32x2",
                    :offset => 4 * 4,
                    :shaderLocation => 1,
                ],
            ],
        ],
    ],
]

vertexAttrib1 = WGPUCore.createEntry(
    WGPUCore.GPUVertexAttribute;
    format = "Float32x4",
    offset = 0,
    shaderLocation = 0,
)

vertexAttrib2 = WGPUCore.createEntry(
    WGPUCore.GPUVertexAttribute;
    format = "Float32x2",
    offset = 16,
    shaderLocation = 1,
)

vertexState = WGPUCore.createEntry(WGPUCore.GPUVertexState; vertexStateOptions...)

vsInternal = vertexState.internal
vs = vsInternal[]
bufs = unsafe_wrap(Vector{WGPUCore.WGPUVertexBufferLayout}, vs.buffers, vs.bufferCount)
buf = bufs[1]
attrs = unsafe_wrap(Vector{WGPUCore.WGPUVertexAttribute}, buf.attributes, buf.attributeCount)

attr1 = unsafe_load(buf.attributes, 1)
attr2 = unsafe_load(buf.attributes, 2)

Test.@testset "VertexAttribute" begin
    Test.@test attr1 == vertexAttrib1.internal |> concrete
    Test.@test attrs == [attr1, attr2]
    Test.@test attr2 == vertexAttrib2.internal |> concrete
end
