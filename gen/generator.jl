using Clang.Generators

arch = lowercase(String(Sys.ARCH))
kernel = lowercase(String(Sys.KERNEL))

releasefile = "wgpu-$kernel-$arch-release.zip"
dirlocation = "$(ENV["HOME"])/.local/lib/"
location = "$(ENV["HOME"])/.local/lib/$releasefile"

url = "https://github.com/gfx-rs/wgpu-native/releases/download/v0.12.0.1/wgpu-$kernel-$arch-release.zip"
@assert download(url, location) == location

run(`unzip $location`)
# run(`rm location`)

cd(@__DIR__)

const WGPU_INCLUDE = dirlocation
const C_HEADERS = ["wgpu.h",]
const WGPU_HEADERS = [joinpath(@__DIR__, h) for h in C_HEADERS]

options = load_options(joinpath(@__DIR__, "generator.toml"))

args = get_default_args()
push!(args, "-IWGPU_INCLUDE")

ctx = create_context(WGPU_HEADERS, args, options)

build!(ctx)


