## Load WGPU
using WGPUCore
using Test
using WGPUNative
using GLFW

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

canvas = WGPUCore.defaultCanvas(WGPUCore.WGPUCanvas);
gpuDevice = WGPUCore.getDefaultDevice();
shadercode = WGPUCore.loadWGSL(shaderSource) |> first;
cshader =
    Ref(WGPUCore.createShaderModule(gpuDevice, "shadercode", shadercode, nothing, nothing));

bindingLayouts = []
bindings = []
cBindingLayoutsList = Ref(WGPUCore.makeLayoutEntryList(bindingLayouts))
cBindingsList = Ref(WGPUCore.makeBindGroupEntryList(bindings))
bindGroupLayout =
    WGPUCore.createBindGroupLayout(gpuDevice, "Bind Group Layout", cBindingLayoutsList[])
bindGroup = WGPUCore.createBindGroup("BindGroup", gpuDevice, bindGroupLayout, cBindingsList[])

if bindGroupLayout.internal[] == C_NULL
    bindGroupLayouts = C_NULL
else
    bindGroupLayouts = map((x) -> x.internal[], [bindGroupLayout])
end

pipelineLayout = WGPUCore.createPipelineLayout(gpuDevice, "PipeLineLayout", bindGroupLayout)
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
    Test.@test unsafe_string(fs.entryPoint) == "fs_main"
end


GLFW.DestroyWindow(canvas.windowRef[])
