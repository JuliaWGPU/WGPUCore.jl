using WGPUCore
using Documenter

DocMeta.setdocmeta!(WGPUCore, :DocTestSetup, :(using WGPUCore); recursive=true)

makedocs(;
    modules=[WGPUCore],
    authors="arhik <arhik23@gmail.com> and contributors",
    repo="https://github.com/JuliaWGPU/WGPUCore.jl/blob/{commit}{path}#{line}",
    sitename="WGPUCore.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaWGPU.github.io/WGPUCore.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaWGPU/WGPUCore.jl",
    devbranch="main",
)
