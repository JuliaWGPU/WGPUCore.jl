# GC.gc()
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

GC.gc()

vertexState = WGPUCore.createEntry(WGPUCore.GPUVertexState; vertexStateOptions...)

vsInternal = vertexState.internal
vs = vsInternal[]

GC.gc()

bufs = unsafe_wrap(Vector{WGPUCore.WGPUVertexBufferLayout}, vs.buffers, vs.bufferCount)
buf = bufs[1]

attrs = unsafe_wrap(Vector{WGPUCore.WGPUVertexAttribute}, buf.attributes, buf.attributeCount)

attr1 = unsafe_load(buf.attributes, 1)
attr2 = unsafe_load(buf.attributes, 2)

GC.gc()

Test.@testset "BufferLayoutTest" begin
    Test.@test buf.attributeCount == 2
    Test.@test (vs.entryPoint |> unsafe_string) == "vs_main"
    Test.@test vs.bufferCount == 1
    Test.@test vs.buffers != C_NULL
    Test.@test attr1 == vertexAttrib1.internal[]
    Test.@test attrs == [attr1, attr2]
    Test.@test attr2 == vertexAttrib2.internal[]
end
