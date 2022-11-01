using GLFW_jll
using GLFW
using Pkg.Artifacts

glfwpath = pkgdir(GLFW_jll)
artifact_toml = joinpath(glfwpath, "Artifacts.toml")
glfwHash = artifact_hash("GLFW", artifact_toml)
glfwlibpath = joinpath(artifact_path(glfwHash), "lib")

arch = begin
	curArch = nothing
	if Sys.ARCH == :aarch64
		curArch =	"arm64"
	elseif Sys.ARCH == :x64 # TODO check
		curArch = "x86_64"
	end
	curArch
end

function build(arch)

	out = Pipe()
	err = Pipe()


	cmd = `brew --prefix glfw`

	process = run(pipeline(ignorestatus(cmd), stdout=out, stderr=err))
	close(out.in)
	close(err.in)
	brewpath = joinpath(String(read(out)) |> strip, "include")
	error = String(read(err))
	code = process.exitcode

	cmd = `clang -arch $(arch) -dynamiclib cocoa.m 
		-I $(brewpath) -o cocoa.dylib 
		-framework cocoa 
		-L $glfwlibpath 
		-lGLFW -framework AppKit -framework Metal -framework QuartzCore`

	out = Pipe()
	err = Pipe()

	process = run(pipeline(ignorestatus(cmd), stdout=out, stderr=err))

	close(out.in)
	close(err.in)

	code = process.exitcode

	if code == 0
		@info "Compiled $arch Cocoa Artifact"
	else
		@error "Compilation failed"
	end 
end

if abspath(PROGRAM_FILE) == @__FILE__
	build(arch)
end

