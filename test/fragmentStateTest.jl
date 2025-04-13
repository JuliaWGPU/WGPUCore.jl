## Load WGPU
using WGPUCore
using Test
using WGPUNative

WGPUCore.SetLogLevel(WGPULogLevel_Off)

shaderSource = Vector{UInt8}(
    """
    struct VertexInput {
        @builtin(vertex_index) vertex_index : u32,
    };
    struct VertexOutput {
        @location(0) color : vec4<f32>,
        @builtin(position) pos: vec4<f32>,
    };

    @vertex
    fn vs_main(in: VertexInput) -> VertexOutput {
        var positions = array<vec2<f32>, 3>(vec2<f32>(0.0, -0.5), vec2<f32>(0.5, 0.5), vec2<f32>(-0.5, 0.7));
        let index = i32(in.vertex_index);
        let p: vec2<f32> = positions[index];

        var out: VertexOutput;
        out.pos = vec4<f32>(sin(p), 0.0, 1.0);
        out.color = vec4<f32>(p, 0.5, 1.0);
        return out;
    }

    @fragment
    fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
        return in.color;
    }
    """,
);

canvas = WGPUCore.getCanvas();
gpuDevice = WGPUCore.getDefaultDevice(canvas);
shaderinfo = WGPUCore.loadWGSL(shaderSource);
cshader =
    Ref(WGPUCore.createShaderModule(gpuDevice, "shadercode", shaderinfo.shaderModuleDesc, nothing, nothing));

bindingLayouts = []
bindings = []

pipelineLayout = WGPUCore.createPipelineLayout(gpuDevice, "PipeLineLayout", bindingLayouts, bindings)
swapChainFormat = WGPUCore.getPreferredFormat(canvas)

fStateOptions =
    WGPUCore.GPUFragmentState => [
        :_module => cshader[],
        :entryPoint => "fs_main",
        :targets => [
            WGPUCore.GPUColorTargetState => [
                :format => swapChainFormat,
                :color => [:srcFactor => "One", :dstFactor => "Zero", :operation => "Add"],
                :alpha => [:srcFactor => "One", :dstFactor => "Zero", :operation => "Add"],
            ],
        ],
    ]

fstate = WGPUCore.createEntry(fStateOptions.first; fStateOptions.second...)

fs = unsafe_load(fstate.internal[] |> ptr)

Test.@testset "FragmentState" begin
    Test.@test unsafe_string(fs.entryPoint.data, fs.entryPoint.length) == "fs_main"
end
