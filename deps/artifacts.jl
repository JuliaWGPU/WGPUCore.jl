using Debugger
using Downloads

include("build.jl")

using Tar, Inflate, SHA

arch = lowercase(String(Sys.ARCH))
kernel = lowercase(String(Sys.KERNEL))

# modifying conventions for wgpu specifically based on
# releases at https://github.com/gfx-rs/wgpu-native/releases/tag/v0.12.0.1

version = "v0.1.2"
kernels = ["macos"]
archs = ["arm64", "x86_64"]

io = IOBuffer()

function writeIO(io, arch, kernel, sha1, sha256, filename, url)
    write(
        io,
        """
        [[Cocoa]]
        arch = "$arch"
        git-tree-sha1 = "$sha1"
        os = "$kernel"

        	[[Cocoa.download]]
        	sha256 = "$sha256"
        	url = "$url"

        """,
    )
end

remoteurl = "https://github.com/dvijaha/WGPUCore.jl/releases/download/v0.1.2"

function generateArtifacts()
    for kernel in kernels
        for arch in archs
            tarfile = "WGPUCore.$version.$(arch)-$(kernel).tar.gz"
            try
                run(`rm cocoa.dylib`)
                build(arch)
                run(`tar -czvf $tarfile cocoa.dylib`)
                run(`rm cocoa.dylib`)
            catch(e)
                println("$e")
            end
        end
    end
end

function writeArtifactsTOML()
    for kernel in kernels
        for arch in archs
            tarfile = "WGPUCore.$version.$(arch)-$(kernel).tar.gz"
            try
                Downloads.download(joinpath(remoteurl, tarfile), tarfile)
                @info joinpath(remoteurl, tarfile)
                sha256Val = bytes2hex(open(sha256, tarfile))
                sha1Val = Tar.tree_hash(IOBuffer(inflate_gzip(tarfile)))
                writeIO(
                    io,
                    arch,
                    kernel,
                    sha1Val,
                    sha256Val,
                    "",
                    joinpath(remoteurl, tarfile),
                )
            catch e 
                println("$e")
            end
        end
    end
    seek(io, 0)
    f = open("Artifacts.toml", "w")
    write(f, io)
    close(f)
end

generateArtifacts()
@info """
	Please upload files while I wait for input
"""
readline()
writeArtifactsTOML()

run(`mv Artifacts.toml ../`)
